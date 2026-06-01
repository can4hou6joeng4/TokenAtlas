import Foundation
import Testing
@testable import TokenAtlas

@Suite("Legacy feature data cleaner")
struct LegacyFeatureDataCleanerTests {
    @Test("Removes legacy feature data and ignores missing directories")
    func removesLegacyFeatureData() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyFeatureDataCleanerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "LegacyFeatureDataCleanerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tokenTownDirectory = root
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("TokenTown", isDirectory: true)
        let stateDirectory = tokenTownDirectory.appendingPathComponent("v1", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1}"#.utf8)
            .write(to: stateDirectory.appendingPathComponent("state.json"))

        let leaderboardsDirectory = root
            .appendingPathComponent("Claude Stats", isDirectory: true)
            .appendingPathComponent("Leaderboards", isDirectory: true)
        try FileManager.default.createDirectory(at: leaderboardsDirectory, withIntermediateDirectories: true)
        try Data(#"{"scores":[]}"#.utf8)
            .write(to: leaderboardsDirectory.appendingPathComponent("scores.json"))

        let legacyDefaultsKeys = [
            "leaderboardsEnabled",
            "leaderboardNickname",
            "leaderboardAvatarSeed",
            "leaderboardProfileUserHash",
            "leaderboardLastSyncedAt",
            "leaderboardLastSyncError",
        ]
        for key in legacyDefaultsKeys {
            defaults.set("legacy", forKey: key)
        }

        let cleaner = LegacyFeatureDataCleaner(applicationSupportDirectory: root, defaults: defaults)
        cleaner.cleanRemovedFeatureData()

        #expect(!FileManager.default.fileExists(atPath: tokenTownDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: leaderboardsDirectory.path))
        for key in legacyDefaultsKeys {
            #expect(defaults.object(forKey: key) == nil)
        }

        cleaner.cleanRemovedFeatureData()
        #expect(!FileManager.default.fileExists(atPath: tokenTownDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: leaderboardsDirectory.path))
    }

    @Test("Removed town page raw value falls back at navigation normalization")
    func townPageRawValueIsRemoved() {
        #expect(MainPage(rawValue: "town") == nil)
    }

    @Test("Removed local insights page raw value falls back at navigation normalization")
    func localInsightsPageRawValueIsRemoved() {
        #expect(MainPage(rawValue: "leaderboards") == nil)
        #expect(SettingsSection(rawValue: "leaderboards") == nil)
    }
}
