import Foundation

struct CodexProviderCount: Sendable, Hashable, Identifiable {
    let provider: String
    let count: Int

    var id: String { provider }
}

struct CodexProviderSyncSnapshot: Sendable, Hashable {
    let targetProvider: String
    let currentProvider: String
    let availableProviders: [String]
    let rolloutFiles: Int
    let rolloutRewriteNeeded: Int
    let sqliteRows: Int
    let sqliteProviderRowsNeedingSync: Int
    let rolloutProviders: [CodexProviderCount]
    let sqliteProviders: [CodexProviderCount]

    var totalPendingUpdates: Int {
        rolloutRewriteNeeded + sqliteProviderRowsNeedingSync
    }
}

struct CodexProviderSyncResult: Sendable, Hashable {
    let targetProvider: String
    let rolloutFilesRewritten: Int
    let sqliteRowsUpdated: Int
    let backupDirectory: URL?

    var summary: String {
        let backup = backupDirectory?.path ?? "未创建备份"
        return "已同步 \(rolloutFilesRewritten) 个原始会话文件、\(sqliteRowsUpdated) 条本地索引记录。备份：\(backup)"
    }
}

struct CodexRecycleBinSnapshot: Sendable, Hashable {
    let entries: [CodexRecycleBinEntry]

    var recoverableCount: Int {
        entries.filter(\.recoverable).count
    }
}

struct CodexRecycleBinEntry: Sendable, Hashable, Identifiable {
    let token: String
    let sessionID: String
    let title: String?
    let projectCWD: String?
    let schema: String
    let dbPath: String
    let backupPath: String
    let deletedAt: Date?
    let lastActiveAt: Date?
    let recoverable: Bool
    let status: String

    var id: String { token }
}

struct CodexRecycleBinBatchFailure: Sendable, Hashable, Identifiable {
    let token: String
    let message: String

    var id: String { token }
}

struct CodexRecycleBinBatchResult: Sendable, Hashable {
    let message: String
    let succeededTokens: [String]
    let failed: [CodexRecycleBinBatchFailure]
}
