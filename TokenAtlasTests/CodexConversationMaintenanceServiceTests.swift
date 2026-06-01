import Foundation
import Testing
@testable import TokenAtlas

@Suite("Codex conversation maintenance")
struct CodexConversationMaintenanceServiceTests {
    @Test("Previews and syncs rollout and SQLite providers with backup")
    func previewsAndSyncsProviders() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = CodexPaths(homeDirectory: root)
        let rollout = root.appendingPathComponent("sessions/2026/05/27/rollout-2026-05-27T10-00-00-s1.jsonl")
        try TempDir.write(Self.rollout(id: "s1", provider: "CodexPilot", cwd: "/tmp/demo"), to: rollout)
        try TempDir.write(#"model_provider = "CodexPilot""#, to: paths.configURL)
        try Self.makeThreadsDB(paths.stateSQLiteURL, rows: [
            ThreadFixture(id: "s1", title: "Thread", provider: "CodexPilot", cwd: "/old", rolloutPath: rollout.path),
        ])

        let service = CodexConversationMaintenanceService(paths: paths)
        let snapshot = try await service.providerSyncSnapshot(targetProvider: "TokenAtlas")

        #expect(snapshot.currentProvider == "CodexPilot")
        #expect(snapshot.rolloutFiles == 1)
        #expect(snapshot.rolloutRewriteNeeded == 1)
        #expect(snapshot.sqliteRows == 1)
        #expect(snapshot.sqliteProviderRowsNeedingSync == 1)

        let result = try await service.runProviderSync(targetProvider: "TokenAtlas")

        #expect(result.rolloutFilesRewritten == 1)
        #expect(result.sqliteRowsUpdated == 1)
        #expect(result.backupDirectory != nil)
        #expect(FileManager.default.fileExists(atPath: result.backupDirectory!.appendingPathComponent("session-meta-backup.json").path))

        let updatedRollout = try String(contentsOf: rollout, encoding: .utf8)
        #expect(updatedRollout.contains(#""model_provider":"TokenAtlas""#))

        let db = try SQLiteConnection(url: paths.stateSQLiteURL)
        let statement = try db.prepare("SELECT model_provider, cwd, has_user_event FROM threads WHERE id = 's1'")
        #expect(try statement.step())
        #expect(statement.columnString(0) == "TokenAtlas")
        #expect(statement.columnString(1) == "/tmp/demo")
        #expect(statement.columnInt(2) == 1)
    }

    @Test("Provider sync lock prevents concurrent rewrites")
    func providerSyncLockPreventsConcurrentRewrites() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = CodexPaths(homeDirectory: root)
        let rollout = root.appendingPathComponent("sessions/2026/05/27/rollout-2026-05-27T10-00-00-lock.jsonl")
        try TempDir.write(Self.rollout(id: "lock", provider: "CodexPilot", cwd: "/tmp/demo"), to: rollout)
        try FileManager.default.createDirectory(at: paths.providerSyncLockDirectory, withIntermediateDirectories: true)

        do {
            _ = try await CodexConversationMaintenanceService(paths: paths).runProviderSync(targetProvider: "TokenAtlas")
            Issue.record("Expected provider sync to reject an existing lock")
        } catch let error as CodexConversationMaintenanceError {
            #expect(error.errorDescription == CodexConversationMaintenanceError.syncAlreadyRunning.errorDescription)
        }

        let unchanged = try String(contentsOf: rollout, encoding: .utf8)
        #expect(unchanged.contains(#""model_provider":"CodexPilot""#))
    }

    @Test("Provider sync rolls rollout files back when SQLite update fails")
    func providerSyncRollsBackRolloutsWhenSQLiteFails() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = CodexPaths(homeDirectory: root)
        let rollout = root.appendingPathComponent("sessions/2026/05/27/rollout-2026-05-27T10-00-00-rollback.jsonl")
        try TempDir.write(Self.rollout(id: "rollback", provider: "CodexPilot", cwd: "/tmp/demo"), to: rollout)
        try TempDir.write("not a sqlite database", to: paths.stateSQLiteURL)

        await #expect(throws: SQLiteStorageError.self) {
            _ = try await CodexConversationMaintenanceService(paths: paths).runProviderSync(targetProvider: "TokenAtlas")
        }

        let rolledBack = try String(contentsOf: rollout, encoding: .utf8)
        #expect(rolledBack.contains(#""model_provider":"CodexPilot""#))
        #expect(rolledBack.contains(#""model_provider":"TokenAtlas""#) == false)
    }

    @Test("Recycle bin lists, restores, and deletes backups")
    func recycleBinListRestoreDelete() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = CodexPaths(homeDirectory: root)
        let rollout = root.appendingPathComponent("sessions/2026/05/27/rollout-2026-05-27T10-00-00-t1.jsonl")
        try Self.makeThreadsDB(paths.stateSQLiteURL, rows: [])
        let backupURL = paths.codexPilotUndoDirectory.appendingPathComponent("1700000000-t1.json")
        try Self.writeBackup(
            to: backupURL,
            dbPath: paths.stateSQLiteURL.path,
            thread: ThreadFixture(id: "t1", title: "Deleted Thread", provider: "TokenAtlas", cwd: "/tmp/project", rolloutPath: rollout.path),
            fileContent: Self.rollout(id: "t1", provider: "TokenAtlas", cwd: "/tmp/project")
        )

        let service = CodexConversationMaintenanceService(paths: paths)
        let snapshot = try await service.recycleBinSnapshot()

        let entry = try #require(snapshot.entries.first)
        #expect(entry.title == "Deleted Thread")
        #expect(entry.projectCWD == "/tmp/project")
        #expect(entry.recoverable)
        #expect(entry.status == "可恢复")

        let restored = try await service.restoreRecycleBinEntries(tokens: [entry.token])
        #expect(restored.succeededTokens == [entry.token])
        #expect(FileManager.default.fileExists(atPath: backupURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: rollout.path))

        let db = try SQLiteConnection(url: paths.stateSQLiteURL)
        let statement = try db.prepare("SELECT title, model_provider FROM threads WHERE id = 't1'")
        #expect(try statement.step())
        #expect(statement.columnString(0) == "Deleted Thread")
        #expect(statement.columnString(1) == "TokenAtlas")

        try Self.writeBackup(
            to: backupURL,
            dbPath: paths.stateSQLiteURL.path,
            thread: ThreadFixture(id: "t2", title: "Trash", provider: "TokenAtlas", cwd: "/tmp/project", rolloutPath: ""),
            fileContent: nil
        )
        let deleted = try await service.deleteRecycleBinEntries(tokens: ["1700000000-t1"])
        #expect(deleted.succeededTokens == ["1700000000-t1"])
        #expect(FileManager.default.fileExists(atPath: backupURL.path) == false)
    }

    @Test("Recycle bin marks malformed and foreign backups as not recoverable")
    func recycleBinInvalidStates() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = CodexPaths(homeDirectory: root)
        try Self.makeThreadsDB(paths.stateSQLiteURL, rows: [])
        try TempDir.write("{", to: paths.codexPilotUndoDirectory.appendingPathComponent("broken.json"))
        try Self.writeBackup(
            to: paths.codexPilotUndoDirectory.appendingPathComponent("foreign.json"),
            dbPath: "/tmp/other.sqlite",
            thread: ThreadFixture(id: "foreign", title: "Foreign", provider: "TokenAtlas", cwd: "/tmp/project", rolloutPath: ""),
            fileContent: nil
        )

        let snapshot = try await CodexConversationMaintenanceService(paths: paths).recycleBinSnapshot()

        #expect(snapshot.entries.contains { $0.token == "broken" && !$0.recoverable && $0.status == "备份无法解析" })
        #expect(snapshot.entries.contains { $0.token == "foreign" && !$0.recoverable && $0.status == "数据库不匹配" })
    }

    @Test("Recycle restore reports file conflicts")
    func recycleRestoreReportsFileConflict() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = CodexPaths(homeDirectory: root)
        let rollout = root.appendingPathComponent("sessions/2026/05/27/rollout-2026-05-27T10-00-00-conflict.jsonl")
        try TempDir.write("existing", to: rollout)
        try Self.makeThreadsDB(paths.stateSQLiteURL, rows: [])
        try Self.writeBackup(
            to: paths.codexPilotUndoDirectory.appendingPathComponent("conflict.json"),
            dbPath: paths.stateSQLiteURL.path,
            thread: ThreadFixture(id: "conflict", title: "Conflict", provider: "TokenAtlas", cwd: "/tmp/project", rolloutPath: rollout.path),
            fileContent: Self.rollout(id: "conflict", provider: "TokenAtlas", cwd: "/tmp/project")
        )

        let result = try await CodexConversationMaintenanceService(paths: paths).restoreRecycleBinEntries(tokens: ["conflict"])

        #expect(result.succeededTokens.isEmpty)
        #expect(result.failed.first?.message.contains("文件已存在") == true)
        let db = try SQLiteConnection(url: paths.stateSQLiteURL)
        let statement = try db.prepare("SELECT COUNT(*) FROM threads WHERE id = 'conflict'")
        #expect(try statement.step())
        #expect(statement.columnInt(0) == 0)
    }

    private struct ThreadFixture {
        let id: String
        let title: String
        let provider: String
        let cwd: String
        let rolloutPath: String
    }

    private static func rollout(id: String, provider: String, cwd: String) -> String {
        """
        {"timestamp":"2026-05-27T10:00:00.000Z","type":"session_meta","payload":{"id":"\(id)","cwd":"\(cwd)","model_provider":"\(provider)"}}
        {"type":"user_message","message":"hello"}

        """
    }

    private static func makeThreadsDB(_ url: URL, rows: [ThreadFixture]) throws {
        let db = try SQLiteConnection(url: url)
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS threads (
                id TEXT PRIMARY KEY,
                title TEXT,
                model_provider TEXT,
                cwd TEXT,
                rollout_path TEXT,
                has_user_event INTEGER,
                updated_at INTEGER
            )
            """
        )
        for row in rows {
            let insert = try db.prepare(
                """
                INSERT INTO threads (id, title, model_provider, cwd, rollout_path, has_user_event, updated_at)
                VALUES (?1, ?2, ?3, ?4, ?5, 0, 1700000000)
                """
            )
            try insert.bind(row.id, at: 1)
            try insert.bind(row.title, at: 2)
            try insert.bind(row.provider, at: 3)
            try insert.bind(row.cwd, at: 4)
            try insert.bind(row.rolloutPath, at: 5)
            try insert.finish()
        }
    }

    private static func writeBackup(to url: URL, dbPath: String, thread: ThreadFixture, fileContent: String?) throws {
        var tables: [String: Any] = [
            "threads": [[
                "id": thread.id,
                "title": thread.title,
                "model_provider": thread.provider,
                "cwd": thread.cwd,
                "rollout_path": thread.rolloutPath,
                "has_user_event": 1,
                "updated_at": 1_700_000_000,
            ]],
        ]
        if let fileContent, !thread.rolloutPath.isEmpty {
            tables["__files"] = [[
                "path": thread.rolloutPath,
                "content_hex": fileContent.data(using: .utf8)!.map { String(format: "%02x", $0) }.joined(),
            ]]
        }
        let object: [String: Any] = [
            "session_id": thread.id,
            "db_path": dbPath,
            "schema": "codex_threads",
            "tables": tables,
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
