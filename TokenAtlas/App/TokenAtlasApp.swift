import AppKit
import SwiftUI

@main
struct TokenAtlasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .appEnvironment(appDelegate.env)
        } label: {
            MenuBarLabel()
                .appEnvironment(appDelegate.env)
                .background(FloatingStatsCommandBridge())
        }
        .menuBarExtraStyle(.window)

        Window("Share Stats", id: ShareExportView.windowID) {
            ShareExportView()
                .appEnvironment(appDelegate.env)
        }
        .windowResizability(.contentSize)

        Window("Git Activity", id: GitActivityView.windowID) {
            GitActivityView()
                .appEnvironment(appDelegate.env)
                .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 640)
                .stxFont(13)
                .tint(.stxAccent)
        }

        Window("TokenAtlas", id: MainWindowView.windowID) {
            MainWindowView()
                .appEnvironment(appDelegate.env)
                .frame(
                    minWidth: MainWindowDefaults.minWidth,
                    idealWidth: MainWindowDefaults.defaultWidth,
                    minHeight: MainWindowDefaults.minHeight,
                    idealHeight: MainWindowDefaults.defaultHeight
                )
                .stxFont(13)
                .tint(.stxAccent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: MainWindowDefaults.defaultWidth, height: MainWindowDefaults.defaultHeight)
    }
}

enum MainWindowDefaults {
    static let minWidth: CGFloat = 1040
    static let minHeight: CGFloat = 660
    static let defaultWidth: CGFloat = 1320
    static let defaultHeight: CGFloat = 840

    @MainActor
    static func apply(to window: NSWindow, expandIfTooSmall: Bool) {
        window.minSize = NSSize(width: minWidth, height: minHeight)
        guard expandIfTooSmall else { return }

        let contentSize = window.contentLayoutRect.size
        let targetSize = NSSize(
            width: max(contentSize.width, defaultWidth),
            height: max(contentSize.height, defaultHeight)
        )
        guard targetSize.width > contentSize.width + 0.5 || targetSize.height > contentSize.height + 0.5 else {
            return
        }

        let oldFrame = window.frame
        var targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
        targetFrame.origin.x = oldFrame.origin.x
        targetFrame.origin.y = oldFrame.maxY - targetFrame.height
        window.setFrame(targetFrame, display: true)
        window.center()
    }
}

private extension View {
    func appEnvironment(_ env: AppEnvironment) -> some View {
        self
            .environment(env)
            .environment(\.locale, env.preferences.appLanguagePreference.locale)
    }
}
