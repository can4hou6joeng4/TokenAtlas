import Foundation
import ServiceManagement

protocol LaunchAtLoginServicing {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

private struct SystemLaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        }
    }
}

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at login" toggle.
enum LaunchAtLogin {
    private enum DefaultsKey {
        static let didRecordUserChoice = "launchAtLogin.didRecordUserChoice"
    }

    static var isEnabled: Bool {
        SystemLaunchAtLoginService().isEnabled
    }

    static func setEnabled(_ enabled: Bool) {
        _ = setEnabled(enabled, defaults: .standard, service: SystemLaunchAtLoginService())
    }

    @discardableResult
    static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults,
        service: LaunchAtLoginServicing
    ) -> Bool {
        defaults.set(true, forKey: DefaultsKey.didRecordUserChoice)
        do {
            try service.setEnabled(enabled)
            return service.isEnabled == enabled
        } catch {
            Log.app.error("Failed to set launch-at-login to \(enabled): \(error.localizedDescription)")
            return false
        }
    }
}
