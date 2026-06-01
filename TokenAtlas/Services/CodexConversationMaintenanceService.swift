import Foundation
import SQLite3

protocol CodexConversationMaintaining: Sendable {
    func providerSyncSnapshot(targetProvider: String?) async throws -> CodexProviderSyncSnapshot
    func runProviderSync(targetProvider: String) async throws -> CodexProviderSyncResult
    func recycleBinSnapshot() async throws -> CodexRecycleBinSnapshot
    func restoreRecycleBinEntries(tokens: [String]) async throws -> CodexRecycleBinBatchResult
    func deleteRecycleBinEntries(tokens: [String]) async throws -> CodexRecycleBinBatchResult
}

enum CodexConversationMaintenanceError: LocalizedError, Sendable {
    case invalidProvider
    case syncAlreadyRunning
    case missingSQLiteDatabase
    case missingBackup(String)
    case backupDatabaseMismatch(String)
    case malformedBackup(String)
    case restoreConflict(String)

    var errorDescription: String? {
        switch self {
        case .invalidProvider:
            "目标 Provider 不能为空，且只能包含字母、数字、点、下划线或短横线。"
        case .syncAlreadyRunning:
            "已有对话归属同步正在进行，请稍后再试。"
        case .missingSQLiteDatabase:
            "未找到 Codex 本地索引数据库。"
        case .missingBackup(let token):
            "回收站记录不存在：\(token)"
        case .backupDatabaseMismatch(let token):
            "回收站记录属于其他数据库：\(token)"
        case .malformedBackup(let token):
            "回收站备份无法解析：\(token)"
        case .restoreConflict(let message):
            message
        }
    }
}

struct CodexConversationMaintenanceService: CodexConversationMaintaining {
    private let paths: CodexPaths

    init(paths: CodexPaths = .default) {
        self.paths = paths
    }

    func providerSyncSnapshot(targetProvider: String? = nil) async throws -> CodexProviderSyncSnapshot {
        let paths = paths
        let target = try Self.sanitizedProvider(targetProvider) ?? ConfigurationProviderStore.codexManagedProviderKey
        return try await Task.detached(priority: .utility) {
            try Self.inspectProviderSync(paths: paths, targetProvider: target)
        }.value
    }

    func runProviderSync(targetProvider: String) async throws -> CodexProviderSyncResult {
        let paths = paths
        let target = try Self.sanitizedProvider(targetProvider) ?? ConfigurationProviderStore.codexManagedProviderKey
        return try await Task.detached(priority: .utility) {
            try Self.withProviderSyncLock(paths: paths) {
                try Self.runProviderSync(paths: paths, targetProvider: target)
            }
        }.value
    }

    func recycleBinSnapshot() async throws -> CodexRecycleBinSnapshot {
        let paths = paths
        return try await Task.detached(priority: .utility) {
            let entries = try Self.recycleBackupURLs(paths: paths)
                .map { Self.recycleEntry(from: $0, stateSQLiteURL: paths.stateSQLiteURL) }
                .sorted { lhs, rhs in
                    (lhs.deletedAt ?? .distantPast) > (rhs.deletedAt ?? .distantPast)
                }
            return CodexRecycleBinSnapshot(entries: entries)
        }.value
    }

    func restoreRecycleBinEntries(tokens: [String]) async throws -> CodexRecycleBinBatchResult {
        let paths = paths
        let sanitized = try Self.sanitizedTokens(tokens)
        return await Task.detached(priority: .utility) {
            var succeeded: [String] = []
            var failed: [CodexRecycleBinBatchFailure] = []
            for token in sanitized {
                do {
                    try Self.restoreRecycleBackup(token: token, paths: paths)
                    succeeded.append(token)
                } catch {
                    failed.append(CodexRecycleBinBatchFailure(token: token, message: Self.message(for: error)))
                }
            }
            return CodexRecycleBinBatchResult(
                message: Self.batchMessage(action: "恢复", succeeded: succeeded.count, failed: failed),
                succeededTokens: succeeded,
                failed: failed
            )
        }.value
    }

    func deleteRecycleBinEntries(tokens: [String]) async throws -> CodexRecycleBinBatchResult {
        let paths = paths
        let sanitized = try Self.sanitizedTokens(tokens)
        return await Task.detached(priority: .utility) {
            var succeeded: [String] = []
            var failed: [CodexRecycleBinBatchFailure] = []
            for token in sanitized {
                do {
                    let backup = try Self.backupURL(for: token, paths: paths)
                    guard FileManager.default.fileExists(atPath: backup.path) else {
                        throw CodexConversationMaintenanceError.missingBackup(token)
                    }
                    try FileManager.default.removeItem(at: backup)
                    succeeded.append(token)
                } catch {
                    failed.append(CodexRecycleBinBatchFailure(token: token, message: Self.message(for: error)))
                }
            }
            return CodexRecycleBinBatchResult(
                message: Self.batchMessage(action: "永久删除", succeeded: succeeded.count, failed: failed),
                succeededTokens: succeeded,
                failed: failed
            )
        }.value
    }
}

// MARK: - Provider sync

private extension CodexConversationMaintenanceService {
    struct SessionMetaRecord: Sendable, Hashable {
        let fileURL: URL
        let firstLine: String
        let provider: String?
        let sessionID: String?
        let cwd: String?
        let hasUserEvent: Bool
    }

    struct SessionRewriteChange: Sendable {
        let fileURL: URL
        let originalFirstLine: String
        let updatedFirstLine: String
    }

    static func inspectProviderSync(paths: CodexPaths, targetProvider: String) throws -> CodexProviderSyncSnapshot {
        let records = sessionMetaRecords(paths: paths)
        let current = currentProvider(paths: paths) ?? "openai"
        let sqlite = try sqliteProviderSnapshot(paths: paths, targetProvider: targetProvider)

        var rolloutCounts: [String: Int] = [:]
        for record in records {
            rolloutCounts[record.provider ?? "unknown", default: 0] += 1
        }

        let rolloutRewriteNeeded = records.filter { $0.provider != nil && $0.provider != targetProvider }.count
        let available = providerOptions(
            target: targetProvider,
            current: current,
            rollout: rolloutCounts,
            sqlite: Dictionary(uniqueKeysWithValues: sqlite.providerCounts.map { ($0.provider, $0.count) })
        )

        return CodexProviderSyncSnapshot(
            targetProvider: targetProvider,
            currentProvider: current,
            availableProviders: available,
            rolloutFiles: records.count,
            rolloutRewriteNeeded: rolloutRewriteNeeded,
            sqliteRows: sqlite.rows,
            sqliteProviderRowsNeedingSync: sqlite.rowsNeedingSync,
            rolloutProviders: providerCounts(from: rolloutCounts),
            sqliteProviders: sqlite.providerCounts
        )
    }

    static func runProviderSync(paths: CodexPaths, targetProvider: String) throws -> CodexProviderSyncResult {
        let records = sessionMetaRecords(paths: paths)
        let changes = try records.compactMap { record -> SessionRewriteChange? in
            guard let provider = record.provider, provider != targetProvider else { return nil }
            let updated = try updatedSessionMetaLine(record.firstLine, targetProvider: targetProvider)
            return SessionRewriteChange(fileURL: record.fileURL, originalFirstLine: record.firstLine, updatedFirstLine: updated)
        }
        let backupDirectory = try createProviderSyncBackup(paths: paths, targetProvider: targetProvider, changes: changes)
        var rewritten = 0
        do {
            for change in changes {
                try replaceFirstLine(at: change.fileURL, firstLine: change.updatedFirstLine)
                rewritten += 1
            }
            let sqliteRows = try updateSQLiteProvider(paths: paths, targetProvider: targetProvider, records: records)
            try normalizeGlobalState(paths: paths)
            pruneProviderSyncBackups(paths: paths)
            return CodexProviderSyncResult(
                targetProvider: targetProvider,
                rolloutFilesRewritten: rewritten,
                sqliteRowsUpdated: sqliteRows,
                backupDirectory: backupDirectory
            )
        } catch {
            try? restoreSessionChanges(Array(changes.prefix(rewritten)))
            throw error
        }
    }

    static func sessionMetaRecords(paths: CodexPaths) -> [SessionMetaRecord] {
        let roots = [paths.sessionsDirectory, paths.archivedSessionsDirectory]
        return roots
            .flatMap(rolloutFiles)
            .compactMap(readSessionMetaRecord)
    }

    static func rolloutFiles(under root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                out.append(url)
            }
        }
        return out
    }

    static func readSessionMetaRecord(from url: URL) -> SessionMetaRecord? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8),
              let newline = raw.firstIndex(of: "\n") else { return nil }
        let first = String(raw[..<newline])
        guard let data = first.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "session_meta" else { return nil }
        let payload = object["payload"] as? [String: Any]
        return SessionMetaRecord(
            fileURL: url,
            firstLine: first,
            provider: payload?["model_provider"] as? String,
            sessionID: payload?["id"] as? String,
            cwd: payload?["cwd"] as? String,
            hasUserEvent: raw.contains(#""user_message""#) || raw.contains(#""user_input""#)
        )
    }

    static func updatedSessionMetaLine(_ line: String, targetProvider: String) throws -> String {
        guard let data = line.data(using: .utf8),
              var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var payload = object["payload"] as? [String: Any] else {
            throw CodexConversationMaintenanceError.invalidProvider
        }
        payload["model_provider"] = targetProvider
        object["payload"] = payload
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: updated, as: UTF8.self)
    }

    static func replaceFirstLine(at url: URL, firstLine: String) throws {
        let raw = try String(contentsOf: url, encoding: .utf8)
        guard let newline = raw.firstIndex(of: "\n") else { return }
        let rest = raw[newline...]
        try (firstLine + rest).write(to: url, atomically: true, encoding: .utf8)
    }

    static func restoreSessionChanges(_ changes: [SessionRewriteChange]) throws {
        for change in changes {
            try replaceFirstLine(at: change.fileURL, firstLine: change.originalFirstLine)
        }
    }

    static func currentProvider(paths: CodexPaths) -> String? {
        guard let raw = try? String(contentsOf: paths.configURL, encoding: .utf8) else { return nil }
        return rootTomlValue(named: "model_provider", in: raw)
    }

    static func sqliteProviderSnapshot(paths: CodexPaths, targetProvider: String) throws -> (rows: Int, rowsNeedingSync: Int, providerCounts: [CodexProviderCount]) {
        guard FileManager.default.fileExists(atPath: paths.stateSQLiteURL.path) else {
            return (0, 0, [])
        }
        let connection = try SQLiteConnection(url: paths.stateSQLiteURL)
        guard try hasTable(connection, "threads"),
              try hasColumns(connection, table: "threads", columns: ["model_provider"]) else {
            return (0, 0, [])
        }
        let rows = try scalarInt(connection, "SELECT COUNT(*) FROM threads")
        let needingSync = try scalarInt(connection, "SELECT COUNT(*) FROM threads WHERE model_provider IS NOT NULL AND model_provider != ?", targetProvider)
        let statement = try connection.prepare("SELECT COALESCE(model_provider, 'unknown'), COUNT(*) FROM threads GROUP BY COALESCE(model_provider, 'unknown')")
        var counts: [String: Int] = [:]
        while try statement.step() {
            counts[statement.columnString(0) ?? "unknown"] = statement.columnInt(1)
        }
        return (rows, needingSync, providerCounts(from: counts))
    }

    static func updateSQLiteProvider(paths: CodexPaths, targetProvider: String, records: [SessionMetaRecord]) throws -> Int {
        guard FileManager.default.fileExists(atPath: paths.stateSQLiteURL.path) else { return 0 }
        let connection = try SQLiteConnection(url: paths.stateSQLiteURL)
        guard try hasTable(connection, "threads"),
              try hasColumns(connection, table: "threads", columns: ["model_provider"]) else {
            return 0
        }
        let hasCWD = try hasColumns(connection, table: "threads", columns: ["cwd"])
        let hasUserEvent = try hasColumns(connection, table: "threads", columns: ["has_user_event"])
        var updated = 0
        var recordsByID: [String: SessionMetaRecord] = [:]
        for record in records {
            guard let id = record.sessionID, recordsByID[id] == nil else { continue }
            recordsByID[id] = record
        }

        try connection.transaction {
            let updateProvider = try connection.prepare("UPDATE threads SET model_provider = ? WHERE model_provider IS NOT NULL AND model_provider != ?")
            try updateProvider.bind(targetProvider, at: 1)
            try updateProvider.bind(targetProvider, at: 2)
            try updateProvider.finish()
            updated += sqliteChanges(connection)

            for (id, record) in recordsByID {
                if hasCWD, let cwd = record.cwd {
                    let statement = try connection.prepare("UPDATE threads SET cwd = ? WHERE id = ? AND (cwd IS NULL OR cwd != ?)")
                    try statement.bind(cwd, at: 1)
                    try statement.bind(id, at: 2)
                    try statement.bind(cwd, at: 3)
                    try statement.finish()
                }
                if hasUserEvent {
                    let statement = try connection.prepare("UPDATE threads SET has_user_event = ? WHERE id = ?")
                    try statement.bind(record.hasUserEvent ? 1 : 0, at: 1)
                    try statement.bind(id, at: 2)
                    try statement.finish()
                }
            }
        }
        return updated
    }

    static func createProviderSyncBackup(paths: CodexPaths, targetProvider: String, changes: [SessionRewriteChange]) throws -> URL {
        let directory = paths.providerSyncBackupsDirectory.appendingPathComponent(timestampName(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for source in [paths.configURL, paths.globalStateURL, paths.globalStateURL.deletingLastPathComponent().appendingPathComponent(".codex-global-state.json.bak")] {
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(source.lastPathComponent))
            }
        }

        let dbDirectory = directory.appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: paths.stateSQLiteURL.path + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: dbDirectory.appendingPathComponent(source.lastPathComponent))
            }
        }

        let manifest = changes.map {
            [
                "path": $0.fileURL.path,
                "firstLine": $0.originalFirstLine,
            ]
        }
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: directory.appendingPathComponent("session-meta-backup.json"), options: .atomic)
        let metadata: [String: Any] = [
            "createdBy": "TokenAtlas provider sync",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "targetProvider": targetProvider,
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
        return directory
    }

    static func withProviderSyncLock<T>(paths: CodexPaths, body: () throws -> T) throws -> T {
        if FileManager.default.fileExists(atPath: paths.providerSyncLockDirectory.path) {
            throw CodexConversationMaintenanceError.syncAlreadyRunning
        }
        try FileManager.default.createDirectory(at: paths.providerSyncLockDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: paths.providerSyncLockDirectory) }
        return try body()
    }

    static func pruneProviderSyncBackups(paths: CodexPaths, keep: Int = 5) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: paths.providerSyncBackupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = urls.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        for url in sorted.dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func normalizeGlobalState(paths: CodexPaths) throws {
        guard FileManager.default.fileExists(atPath: paths.globalStateURL.path) else { return }
        // TokenAtlas currently does not own a richer global-state contract. Reading and
        // writing the JSON verifies it is syntactically valid while preserving content.
        let data = try Data(contentsOf: paths.globalStateURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try normalized.write(to: paths.globalStateURL, options: .atomic)
    }
}

// MARK: - Recycle bin

private extension CodexConversationMaintenanceService {
    struct BackupPayload {
        let sessionID: String
        let dbPath: String
        let schema: String
        let tables: [String: [[String: Any]]]
        let files: [[String: Any]]
    }

    static func recycleBackupURLs(paths: CodexPaths) throws -> [URL] {
        var urls: [URL] = []
        for directory in [paths.codexPilotUndoDirectory, paths.tokenAtlasUndoDirectory] {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            let entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            urls.append(contentsOf: entries.filter { $0.pathExtension == "json" })
        }
        return urls
    }

    static func recycleEntry(from url: URL, stateSQLiteURL: URL) -> CodexRecycleBinEntry {
        let token = url.deletingPathExtension().lastPathComponent
        let deletedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        guard let payload = try? readBackupPayload(from: url) else {
            return CodexRecycleBinEntry(
                token: token,
                sessionID: tokenSessionID(token),
                title: nil,
                projectCWD: nil,
                schema: "unknown",
                dbPath: stateSQLiteURL.path,
                backupPath: url.path,
                deletedAt: deletedAt,
                lastActiveAt: nil,
                recoverable: false,
                status: "备份无法解析"
            )
        }
        let dbMatches = payload.dbPath == stateSQLiteURL.path
        return CodexRecycleBinEntry(
            token: token,
            sessionID: payload.sessionID,
            title: backupTitle(payload.tables),
            projectCWD: backupProjectCWD(payload.tables),
            schema: payload.schema,
            dbPath: payload.dbPath,
            backupPath: url.path,
            deletedAt: deletedAt,
            lastActiveAt: backupLastActiveAt(payload.tables),
            recoverable: dbMatches,
            status: dbMatches ? "可恢复" : "数据库不匹配"
        )
    }

    static func restoreRecycleBackup(token: String, paths: CodexPaths) throws {
        let url = try backupURL(for: token, paths: paths)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexConversationMaintenanceError.missingBackup(token)
        }
        let payload = try readBackupPayload(from: url)
        guard payload.dbPath == paths.stateSQLiteURL.path else {
            throw CodexConversationMaintenanceError.backupDatabaseMismatch(token)
        }
        guard FileManager.default.fileExists(atPath: paths.stateSQLiteURL.path) else {
            throw CodexConversationMaintenanceError.missingSQLiteDatabase
        }
        let connection = try SQLiteConnection(url: paths.stateSQLiteURL)
        try validateRestoreFiles(payload.files)
        try restoreTables(payload.tables, connection: connection)
        try restoreFiles(payload.files)
        try FileManager.default.removeItem(at: url)
    }

    static func readBackupPayload(from url: URL) throws -> BackupPayload {
        let token = url.deletingPathExtension().lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionID = object["session_id"] as? String,
                  let dbPath = object["db_path"] as? String,
                  let schema = object["schema"] as? String,
                  let rawTables = object["tables"] as? [String: Any] else {
                throw CodexConversationMaintenanceError.malformedBackup(token)
            }
            var tables: [String: [[String: Any]]] = [:]
            var files: [[String: Any]] = []
            for (key, value) in rawTables {
                if key == "__files" {
                    files = value as? [[String: Any]] ?? []
                } else {
                    tables[key] = value as? [[String: Any]] ?? []
                }
            }
            return BackupPayload(sessionID: sessionID, dbPath: dbPath, schema: schema, tables: tables, files: files)
        } catch let error as CodexConversationMaintenanceError {
            throw error
        } catch {
            throw CodexConversationMaintenanceError.malformedBackup(token)
        }
    }

    static func backupURL(for token: String, paths: CodexPaths) throws -> URL {
        for directory in [paths.codexPilotUndoDirectory, paths.tokenAtlasUndoDirectory] {
            let url = directory.appendingPathComponent("\(token).json", isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return paths.codexPilotUndoDirectory.appendingPathComponent("\(token).json", isDirectory: false)
    }

    static func restoreTables(_ tables: [String: [[String: Any]]], connection: SQLiteConnection) throws {
        try validateRestoreTables(tables, connection: connection)
        try connection.transaction {
            try connection.execute("PRAGMA defer_foreign_keys = ON")
            for table in restoreTableOrder(tables) {
                guard let rows = tables[table] else { continue }
                for row in rows {
                    try insertRow(row, table: table, connection: connection)
                }
            }
        }
    }

    static func validateRestoreTables(_ tables: [String: [[String: Any]]], connection: SQLiteConnection) throws {
        for (table, rows) in tables {
            guard try hasTable(connection, table) else {
                throw CodexConversationMaintenanceError.restoreConflict("无法恢复缺失的数据表：\(table)")
            }
            let existing = Set(try tableColumns(connection, table: table))
            for row in rows {
                for column in row.keys where !existing.contains(column) {
                    throw CodexConversationMaintenanceError.restoreConflict("无法恢复缺失的字段：\(table).\(column)")
                }
            }
        }
    }

    static func restoreTableOrder(_ tables: [String: [[String: Any]]]) -> [String] {
        let preferred = [
            "sessions",
            "threads",
            "messages",
            "thread_dynamic_tools",
            "thread_goals",
            "thread_spawn_edges",
            "stage1_outputs",
            "agent_job_items",
        ]
        var seen = Set<String>()
        var ordered = preferred.filter { tables.keys.contains($0) && seen.insert($0).inserted }
        ordered.append(contentsOf: tables.keys.filter { seen.insert($0).inserted }.sorted())
        return ordered
    }

    static func insertRow(_ row: [String: Any], table: String, connection: SQLiteConnection) throws {
        guard !row.isEmpty else { return }
        if table == "agent_job_items", try updateExistingAgentJobItem(row, connection: connection) {
            return
        }
        let columns = row.keys.sorted()
        let columnSQL = columns.map(quoteIdentifier).joined(separator: ", ")
        let placeholders = (1 ... columns.count).map { "?\($0)" }.joined(separator: ", ")
        let statement = try connection.prepare("INSERT INTO \(quoteIdentifier(table)) (\(columnSQL)) VALUES (\(placeholders))")
        for (index, column) in columns.enumerated() {
            try bindJSONValue(row[column] ?? NSNull(), to: statement, at: Int32(index + 1))
        }
        try statement.finish()
    }

    static func updateExistingAgentJobItem(_ row: [String: Any], connection: SQLiteConnection) throws -> Bool {
        guard let id = row["id"], row.keys.contains("assigned_thread_id"), try hasTable(connection, "agent_job_items") else {
            return false
        }
        let select = try connection.prepare("SELECT assigned_thread_id FROM agent_job_items WHERE id = ? LIMIT 1")
        try bindJSONValue(id, to: select, at: 1)
        guard try select.step() else { return false }
        if !select.columnIsNull(0) {
            throw CodexConversationMaintenanceError.restoreConflict("恢复冲突：agent job item 已分配")
        }
        let update = try connection.prepare("UPDATE agent_job_items SET assigned_thread_id = ? WHERE id = ? AND assigned_thread_id IS NULL")
        try bindJSONValue(row["assigned_thread_id"] ?? NSNull(), to: update, at: 1)
        try bindJSONValue(id, to: update, at: 2)
        try update.finish()
        return true
    }

    static func restoreFiles(_ files: [[String: Any]]) throws {
        for file in files {
            guard let path = file["path"] as? String,
                  let content = file["content_hex"] as? String else { continue }
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try decodeHex(content).write(to: url, options: .atomic)
        }
    }

    static func validateRestoreFiles(_ files: [[String: Any]]) throws {
        for file in files {
            guard let path = file["path"] as? String else { continue }
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                throw CodexConversationMaintenanceError.restoreConflict("恢复冲突：文件已存在 \(url.path)")
            }
        }
    }
}

// MARK: - SQLite and parsing helpers

private extension CodexConversationMaintenanceService {
    static func hasTable(_ connection: SQLiteConnection, _ table: String) throws -> Bool {
        let statement = try connection.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1")
        try statement.bind(table, at: 1)
        return try statement.step()
    }

    static func hasColumns(_ connection: SQLiteConnection, table: String, columns: [String]) throws -> Bool {
        let existing = Set(try tableColumns(connection, table: table))
        return columns.allSatisfy { existing.contains($0) }
    }

    static func tableColumns(_ connection: SQLiteConnection, table: String) throws -> [String] {
        let statement = try connection.prepare("PRAGMA table_info(\(quoteIdentifier(table)))")
        var columns: [String] = []
        while try statement.step() {
            if let name = statement.columnString(1) {
                columns.append(name)
            }
        }
        return columns
    }

    static func scalarInt(_ connection: SQLiteConnection, _ sql: String, _ value: String? = nil) throws -> Int {
        let statement = try connection.prepare(sql)
        if let value {
            try statement.bind(value, at: 1)
        }
        guard try statement.step() else { return 0 }
        return statement.columnInt(0)
    }

    static func sqliteChanges(_ connection: SQLiteConnection) -> Int {
        Int(sqlite3_changes(connection.raw))
    }

    static func bindJSONValue(_ value: Any, to statement: SQLiteStatement, at index: Int32) throws {
        switch value {
        case is NSNull:
            try statement.bind(Optional<String>.none, at: index)
        case let value as String:
            try statement.bind(value, at: index)
        case let value as Int:
            try statement.bind(value, at: index)
        case let value as Int64:
            try statement.bind(value, at: index)
        case let value as Double:
            try statement.bind(value, at: index)
        case let value as Bool:
            try statement.bind(value ? 1 : 0, at: index)
        default:
            let data = try JSONSerialization.data(withJSONObject: value)
            try statement.bind(String(decoding: data, as: UTF8.self), at: index)
        }
    }

    static func quoteIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func rootTomlValue(named key: String, in raw: String) -> String? {
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("["),
                  let (name, value) = splitTomlAssignment(trimmed),
                  name == key else { continue }
            return unquoteTomlString(value)
        }
        return nil
    }

    static func splitTomlAssignment(_ line: String) -> (String, String)? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    static func unquoteTomlString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }

    static func providerCounts(from counts: [String: Int]) -> [CodexProviderCount] {
        counts
            .map { CodexProviderCount(provider: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending
            }
    }

    static func providerOptions(target: String, current: String, rollout: [String: Int], sqlite: [String: Int]) -> [String] {
        var values = [target, current, ConfigurationProviderStore.codexManagedProviderKey]
        values.append(contentsOf: rollout.keys)
        values.append(contentsOf: sqlite.keys)
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "unknown" }
            .filter { seen.insert($0).inserted }
    }

    static func sanitizedProvider(_ value: String?) throws -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CodexConversationMaintenanceError.invalidProvider
        }
        return trimmed
    }

    static func sanitizedTokens(_ tokens: [String]) throws -> [String] {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let cleaned = tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ token in token.unicodeScalars.allSatisfy { allowed.contains($0) } }) else {
            throw CodexConversationMaintenanceError.missingBackup("")
        }
        return Array(NSOrderedSet(array: cleaned).compactMap { $0 as? String })
    }

    static func timestampName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    static func tokenSessionID(_ token: String) -> String {
        token.split(separator: "-").dropFirst().joined(separator: "-")
    }

    static func backupTitle(_ tables: [String: [[String: Any]]]) -> String? {
        firstRow(tables, "threads")?["title"] as? String
            ?? firstRow(tables, "sessions")?["title"] as? String
    }

    static func backupProjectCWD(_ tables: [String: [[String: Any]]]) -> String? {
        firstRow(tables, "threads")?["cwd"] as? String
            ?? firstRow(tables, "sessions")?["cwd"] as? String
    }

    static func backupLastActiveAt(_ tables: [String: [[String: Any]]]) -> Date? {
        let row = firstRow(tables, "threads") ?? firstRow(tables, "sessions")
        let raw = row?["updated_at"] ?? row?["last_active_at"] ?? row?["created_at"]
        if let double = raw as? Double { return Date(timeIntervalSince1970: double) }
        if let int = raw as? Int { return Date(timeIntervalSince1970: TimeInterval(int)) }
        if let int64 = raw as? Int64 { return Date(timeIntervalSince1970: TimeInterval(int64)) }
        return nil
    }

    static func firstRow(_ tables: [String: [[String: Any]]], _ table: String) -> [String: Any]? {
        tables[table]?.first
    }

    static func decodeHex(_ value: String) throws -> Data {
        var data = Data()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2, limitedBy: value.endIndex) ?? value.endIndex
            guard next <= value.endIndex else { break }
            let byteString = value[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw CodexConversationMaintenanceError.restoreConflict("备份文件内容无法解码")
            }
            data.append(byte)
            index = next
        }
        return data
    }

    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return error.localizedDescription
    }

    static func batchMessage(action: String, succeeded: Int, failed: [CodexRecycleBinBatchFailure]) -> String {
        if failed.isEmpty {
            return "已\(action) \(succeeded) 条回收站记录。"
        }
        let messages = failed.map(\.message).joined(separator: "；")
        return "已\(action) \(succeeded) 条，\(failed.count) 条失败：\(messages)"
    }
}
