import Foundation
import Testing
@testable import TokenAtlas

@Suite("Launch at login")
struct LaunchAtLoginTests {
    @Test("Setting launch at login is explicit and records user choice")
    func setEnabledRecordsExplicitUserChoice() throws {
        let defaults = try makeDefaults()
        let service = FakeLaunchAtLoginService()

        let didApply = LaunchAtLogin.setEnabled(true, defaults: defaults, service: service)

        #expect(didApply)
        #expect(defaults.bool(forKey: "launchAtLogin.didRecordUserChoice"))
        #expect(service.requestedValues == [true])
    }

    @Test("Failed launch at login changes still record the explicit user choice")
    func setEnabledFailureStillRecordsExplicitUserChoice() throws {
        let defaults = try makeDefaults()
        let service = FakeLaunchAtLoginService(error: CocoaError(.featureUnsupported))

        let didApply = LaunchAtLogin.setEnabled(true, defaults: defaults, service: service)

        #expect(!didApply)
        #expect(defaults.bool(forKey: "launchAtLogin.didRecordUserChoice"))
        #expect(service.requestedValues == [true])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "TokenAtlasTests.LaunchAtLogin.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    private(set) var requestedValues: [Bool] = []
    private let error: Error?
    private var enabled = false

    init(error: Error? = nil) {
        self.error = error
    }

    var isEnabled: Bool { enabled }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        if let error { throw error }
        self.enabled = enabled
    }
}
