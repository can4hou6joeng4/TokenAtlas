import Foundation

/// Where the OpenAI Codex CLI keeps its data on disk. Injectable so tests can
/// point it at a temp directory.
struct CodexPaths: Sendable, Hashable {
    /// `~/.codex` (or `$CODEX_HOME` when set).
    let homeDirectory: URL

    /// `<homeDirectory>/sessions` — rollout transcripts under `YYYY/MM/DD/`.
    var sessionsDirectory: URL { homeDirectory.appendingPathComponent("sessions", isDirectory: true) }

    /// `<homeDirectory>/archived_sessions` — archived rollout transcripts.
    var archivedSessionsDirectory: URL { homeDirectory.appendingPathComponent("archived_sessions", isDirectory: true) }

    /// `<homeDirectory>/state_5.sqlite` — Codex Desktop's local thread index.
    var stateSQLiteURL: URL { homeDirectory.appendingPathComponent("state_5.sqlite", isDirectory: false) }

    var configURL: URL { homeDirectory.appendingPathComponent("config.toml", isDirectory: false) }

    var globalStateURL: URL { homeDirectory.appendingPathComponent(".codex-global-state.json", isDirectory: false) }

    var providerSyncLockDirectory: URL { homeDirectory.appendingPathComponent("tmp/provider-sync.lock", isDirectory: true) }

    var providerSyncBackupsDirectory: URL { homeDirectory.appendingPathComponent("backups_state/provider-sync", isDirectory: true) }

    /// CodexPilot-compatible undo backups for local conversation deletion.
    var codexPilotUndoDirectory: URL { homeDirectory.appendingPathComponent(".codex-pilot-undo", isDirectory: true) }

    /// TokenAtlas-owned undo backups for future delete-to-recycle-bin support.
    var tokenAtlasUndoDirectory: URL { homeDirectory.appendingPathComponent(".tokenatlas-undo", isDirectory: true) }

    init(homeDirectory: URL) { self.homeDirectory = homeDirectory }

    static let `default`: CodexPaths = {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return CodexPaths(homeDirectory: URL(fileURLWithPath: override, isDirectory: true))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return CodexPaths(homeDirectory: home.appendingPathComponent(".codex", isDirectory: true))
    }()
}
