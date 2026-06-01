import Foundation

struct LegacyFeatureDataCleaner {
    private let applicationSupportDirectory: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(
        applicationSupportDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    func cleanRemovedFeatureData() {
        removeLegacyTokenTownData()
        removeLegacyLeaderboardsData()
        removeLegacyLeaderboardDefaults()
    }

    private func removeLegacyTokenTownData() {
        let tokenTownDirectory = applicationSupportDirectory
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("TokenTown", isDirectory: true)
        guard fileManager.fileExists(atPath: tokenTownDirectory.path) else { return }

        do {
            try fileManager.removeItem(at: tokenTownDirectory)
            Log.app.info("Removed legacy TokenTown data at \(tokenTownDirectory.path, privacy: .public)")
        } catch {
            Log.app.error("Failed to remove legacy TokenTown data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeLegacyLeaderboardsData() {
        let leaderboardsDirectory = applicationSupportDirectory
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("Leaderboards", isDirectory: true)
        guard fileManager.fileExists(atPath: leaderboardsDirectory.path) else { return }

        do {
            try fileManager.removeItem(at: leaderboardsDirectory)
            Log.app.info("Removed legacy Leaderboards data at \(leaderboardsDirectory.path, privacy: .public)")
        } catch {
            Log.app.error("Failed to remove legacy Leaderboards data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeLegacyLeaderboardDefaults() {
        for key in Self.legacyLeaderboardDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private static let legacyLeaderboardDefaultsKeys = [
        "leaderboardsEnabled",
        "leaderboardNickname",
        "leaderboardAvatarSeed",
        "leaderboardProfileUserHash",
        "leaderboardLastSyncedAt",
        "leaderboardLastSyncError",
    ]
}
