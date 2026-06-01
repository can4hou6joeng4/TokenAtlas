import AtollEmbed
import SwiftUI

struct NotchIslandSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    var onSelectSection: (SettingsSection) -> Void = { _ in }
    @SceneStorage("notchIslandSettings.selectedTab") private var selectedTabRaw = NotchIslandSettingsTab.island.rawValue
    @State private var settingsRefreshToken = 0

    private var selectedTab: NotchIslandSettingsTab {
        NotchIslandSettingsTab(rawValue: selectedTabRaw) ?? .island
    }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 0) {
            Text(NotchIslandLocalization.text("Notch Island", zh: "刘海岛", locale: locale))
                .font(.sora(28, weight: .semibold))
                .padding(.bottom, 18)

            Rectangle()
                .fill(Color.stxStroke)
                .frame(height: 1)

            HStack(spacing: 0) {
                NotchIslandSettingsSidebar(
                    selection: selectedTabBinding,
                    enabledModules: prefs.notchIslandEnabledModules,
                    locale: locale
                )
                .frame(width: 232)
                .frame(maxHeight: .infinity, alignment: .top)

                Rectangle()
                    .fill(Color.stxStroke)
                    .frame(width: 1)

                NotchIslandSettingsDetailPane(
                    tab: selectedTab,
                    preferences: prefs,
                    isFeatureEnabled: prefs.notchIslandEnabled,
                    refreshToken: settingsRefreshToken,
                    locale: locale,
                    onSelectSection: onSelectSection,
                    onSettingChanged: noteSettingChanged
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 28)
        .onChange(of: selectedTabRaw) { _, _ in
            noteSettingChanged()
        }
    }

    private var selectedTabBinding: Binding<NotchIslandSettingsTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    private func noteSettingChanged() {
        settingsRefreshToken &+= 1
    }
}

enum NotchIslandSettingsGroup: String, CaseIterable, Identifiable {
    case core
    case live
    case utilities
    case system
    case integrations

    var id: String { rawValue }

    var title: String? { title() }

    func title(locale: Locale? = nil) -> String? {
        switch self {
        case .core: nil
        case .live: NotchIslandLocalization.text("LIVE", zh: "实时", locale: locale)
        case .utilities: NotchIslandLocalization.text("UTILITIES", zh: "工具", locale: locale)
        case .system: NotchIslandLocalization.text("SYSTEM", zh: "系统", locale: locale)
        case .integrations: NotchIslandLocalization.text("INTEGRATIONS", zh: "集成", locale: locale)
        }
    }
}

enum NotchIslandSettingsTab: String, CaseIterable, Identifiable {
    case island
    case appearance
    case media
    case stats
    case timer
    case clipboard
    case colorPicker
    case calendar
    case shelf
    case privacy
    case recording
    case focus
    case battery
    case bluetooth
    case downloads
    case osd
    case lockScreenWidgets
    case extensionBridge
    case screenAssistant

    var id: String { rawValue }

    var title: String { title() }

    func title(locale: Locale? = nil) -> String {
        switch self {
        case .island: NotchIslandLocalization.atollText("Island", locale: locale)
        case .appearance: NotchIslandLocalization.atollText("Appearance", locale: locale)
        case .media: NotchIslandLocalization.atollText("Media", locale: locale)
        case .stats: NotchIslandLocalization.atollText("Stats", locale: locale)
        case .timer: NotchIslandLocalization.atollText("Timer", locale: locale)
        case .clipboard: NotchIslandLocalization.atollText("Clipboard", locale: locale)
        case .colorPicker: NotchIslandLocalization.atollText("Color Picker", locale: locale)
        case .calendar: NotchIslandLocalization.atollText("Calendar", locale: locale)
        case .shelf: NotchIslandLocalization.atollText("Shelf", locale: locale)
        case .privacy: NotchIslandLocalization.atollText("Privacy", locale: locale)
        case .recording: NotchIslandLocalization.atollText("Recording", locale: locale)
        case .focus: NotchIslandLocalization.atollText("Focus", locale: locale)
        case .battery: NotchIslandLocalization.atollText("Battery", locale: locale)
        case .bluetooth: NotchIslandLocalization.atollText("Bluetooth", locale: locale)
        case .downloads: NotchIslandLocalization.atollText("Downloads", locale: locale)
        case .osd: "OSD"
        case .lockScreenWidgets: NotchIslandLocalization.atollText("Lock Widgets", locale: locale)
        case .extensionBridge: NotchIslandLocalization.atollText("Extensions", locale: locale)
        case .screenAssistant: NotchIslandLocalization.atollText("Screen Assistant", locale: locale)
        }
    }

    var symbol: String {
        switch self {
        case .island: "capsule.portrait.tophalf.filled"
        case .appearance: "paintpalette"
        case .media: "music.note"
        case .stats: "cpu"
        case .timer: "timer"
        case .clipboard: "doc.on.clipboard"
        case .colorPicker: "eyedropper"
        case .calendar: "calendar"
        case .shelf: "tray.and.arrow.down"
        case .privacy: "web.camera"
        case .recording: "record.circle"
        case .focus: "moon"
        case .battery: "battery.75percent"
        case .bluetooth: "headphones"
        case .downloads: "arrow.down.circle"
        case .osd: "slider.horizontal.3"
        case .lockScreenWidgets: "lock.display"
        case .extensionBridge: "puzzlepiece.extension"
        case .screenAssistant: "sparkles"
        }
    }

    var group: NotchIslandSettingsGroup {
        switch self {
        case .island, .appearance: .core
        case .media, .stats, .timer, .calendar, .privacy, .recording, .focus, .battery: .live
        case .clipboard, .colorPicker, .shelf, .downloads, .osd: .utilities
        case .bluetooth, .lockScreenWidgets: .system
        case .extensionBridge, .screenAssistant: .integrations
        }
    }

    var module: NotchIslandModule? {
        switch self {
        case .island, .appearance:
            nil
        case .media:
            .media
        case .stats:
            .stats
        case .timer:
            .timer
        case .clipboard:
            .clipboard
        case .colorPicker:
            .colorPicker
        case .calendar:
            .calendar
        case .shelf:
            .shelf
        case .privacy:
            .privacy
        case .recording:
            .recording
        case .focus:
            .focus
        case .battery:
            .battery
        case .bluetooth:
            .bluetooth
        case .downloads:
            .downloads
        case .osd:
            .osd
        case .lockScreenWidgets:
            .lockScreenWidgets
        case .extensionBridge:
            .extensionBridge
        case .screenAssistant:
            .screenAssistant
        }
    }

    var bridgeTab: AtollSettingsTabID {
        AtollSettingsTabID(rawValue: rawValue) ?? .island
    }

    var subtitle: String { subtitle() }

    func subtitle(locale: Locale? = nil) -> String {
        if let module {
            return module.settingsDescription(locale: locale)
        }
        switch self {
        case .island:
            return NotchIslandLocalization.text(
                "Window placement, sizing, hover behavior, and shortcuts.",
                zh: "窗口位置、尺寸、悬停行为和快捷键。",
                locale: locale
            )
        case .appearance:
            return NotchIslandLocalization.text(
                "Visual effects, chrome, media tinting, and idle details.",
                zh: "视觉效果、外观、媒体染色和空闲细节。",
                locale: locale
            )
        default:
            return ""
        }
    }

    static var grouped: [(group: NotchIslandSettingsGroup, tabs: [NotchIslandSettingsTab])] {
        NotchIslandSettingsGroup.allCases.compactMap { group in
            let tabs = allCases.filter { $0.group == group }
            return tabs.isEmpty ? nil : (group, tabs)
        }
    }
}

#if DEBUG
#Preview("Notch Island Settings") {
    NotchIslandSettingsView()
        .environment(AppEnvironment.preview())
        .frame(width: 980, height: 680)
}
#endif
