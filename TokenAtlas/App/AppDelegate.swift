import AppKit

/// Owns the ``AppEnvironment`` and kicks off the first scan once AppKit has
/// finished launching. `MenuBarExtra`'s label/window views don't run a normal
/// `onAppear`/`task` lifecycle at launch, so the kickoff lives here instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env: AppEnvironment

    override init() {
        self.env = MainActor.assumeIsolated {
            AppEnvironment()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Theme.registerFonts()
            env.start()
        }
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where env.handleOpenURL(url) {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let firstURL = urls.first {
            Log.app.notice("Unhandled application URL: \(firstURL.absoluteString, privacy: .public)")
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
