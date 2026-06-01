import Foundation

/// Categories shown in the main window's "settings mode" sidebar. Each owns
/// the corresponding `*SettingsView` rendered in the detail panel.
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case features
    case menuBar
    case notchIsland
    case platforms
    case tracking
    case dictionary
    case github
    case about

    var id: String { rawValue }

    static var visibleSidebarSections: [SettingsSection] {
        allCases.filter { $0 != .dictionary }
    }

    var isVisibleInSidebar: Bool {
        Self.visibleSidebarSections.contains(self)
    }

    var title: String {
        switch self {
        case .general:   L10n.string("settings.section.general", defaultValue: "General")
        case .features:  L10n.string("settings.section.features", defaultValue: "Features")
        case .menuBar:   L10n.string("settings.section.menu_bar", defaultValue: "Menu Bar")
        case .notchIsland: L10n.string("settings.section.notch_island", defaultValue: "Notch Island")
        case .platforms: L10n.string("settings.section.platforms", defaultValue: "Platforms")
        case .tracking:  L10n.string("settings.section.tracking", defaultValue: "Tracking")
        case .dictionary: "Analysis Terms"
        case .github:    "GitHub"
        case .about:     L10n.string("settings.section.about", defaultValue: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general:   "gearshape"
        case .features:  "switch.2"
        case .menuBar:   "menubar.rectangle"
        case .notchIsland: "capsule.portrait.tophalf.filled"
        case .platforms: "square.stack.3d.up"
        case .tracking:  "waveform.path.ecg"
        case .dictionary: "text.book.closed"
        case .github:    "chevron.left.forwardslash.chevron.right"
        case .about:     "info.circle"
        }
    }

    var assetName: String? {
        nil
    }
}
