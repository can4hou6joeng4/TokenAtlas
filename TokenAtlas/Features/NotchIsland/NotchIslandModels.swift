import AppKit
import Foundation

enum NotchIslandDisplayMode: String, CaseIterable, Sendable, Identifiable {
    case primaryDisplay
    case pointerDisplay
    case allDisplays

    var id: String { rawValue }

    var displayName: String { displayName() }

    func displayName(locale: Locale? = nil) -> String {
        switch self {
        case .primaryDisplay: NotchIslandLocalization.text("Primary Display", zh: "主显示器", locale: locale)
        case .pointerDisplay: NotchIslandLocalization.text("Pointer Display", zh: "指针所在显示器", locale: locale)
        case .allDisplays: NotchIslandLocalization.text("All Displays", zh: "所有显示器", locale: locale)
        }
    }

    var description: String { description() }

    func description(locale: Locale? = nil) -> String {
        switch self {
        case .primaryDisplay: NotchIslandLocalization.atollText("Pin the island to the main screen.", locale: locale)
        case .pointerDisplay: NotchIslandLocalization.text("Move the island to the screen under the pointer.", zh: "将刘海岛移动到指针所在的显示器。", locale: locale)
        case .allDisplays: NotchIslandLocalization.atollText("Show a separate island on every connected display.", locale: locale)
        }
    }
}

enum NotchIslandSizePreset: String, CaseIterable, Sendable, Identifiable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var displayName: String { displayName() }

    func displayName(locale: Locale? = nil) -> String {
        switch self {
        case .compact: NotchIslandLocalization.atollText("Compact", locale: locale)
        case .regular: NotchIslandLocalization.atollText("Regular", locale: locale)
        case .large: NotchIslandLocalization.atollText("Large", locale: locale)
        }
    }

    var description: String { description() }

    func description(locale: Locale? = nil) -> String {
        switch self {
        case .compact: NotchIslandLocalization.atollText("Small top pill with a focused expanded panel.", locale: locale)
        case .regular: NotchIslandLocalization.atollText("Balanced size for media, stats, and utilities.", locale: locale)
        case .large: NotchIslandLocalization.atollText("More room for lists, shelf items, and lock-screen widgets.", locale: locale)
        }
    }
}

enum NotchIslandScreenStyle: String, CaseIterable, Sendable, Identifiable {
    case sameAsNotch
    case floatingIsland

    var id: String { rawValue }

    var displayName: String { displayName() }

    func displayName(locale: Locale? = nil) -> String {
        switch self {
        case .sameAsNotch: NotchIslandLocalization.atollText("Same as notch", locale: locale)
        case .floatingIsland: NotchIslandLocalization.atollText("Floating island", locale: locale)
        }
    }

    var description: String { description() }

    func description(locale: Locale? = nil) -> String {
        switch self {
        case .sameAsNotch: NotchIslandLocalization.atollText("Blend into the top screen edge.", locale: locale)
        case .floatingIsland: NotchIslandLocalization.atollText("Float below the top edge as a detached pill.", locale: locale)
        }
    }
}

struct NotchIslandScreenDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let localizedName: String
    let hasPhysicalNotch: Bool
}

enum NotchIslandScreenStyleResolver {
    static func effectiveStyle(
        screenID: String,
        hasPhysicalNotch: Bool,
        storedStyles: [String: NotchIslandScreenStyle]
    ) -> NotchIslandScreenStyle {
        if hasPhysicalNotch {
            return .sameAsNotch
        }
        return storedStyles[screenID] ?? .sameAsNotch
    }

    static func effectiveStyles(
        for descriptors: [NotchIslandScreenDescriptor],
        storedStyles: [String: NotchIslandScreenStyle]
    ) -> [String: NotchIslandScreenStyle] {
        descriptors.reduce(into: [:]) { result, descriptor in
            result[descriptor.id] = effectiveStyle(
                screenID: descriptor.id,
                hasPhysicalNotch: descriptor.hasPhysicalNotch,
                storedStyles: storedStyles
            )
        }
    }
}

@MainActor
enum NotchIslandScreenCatalog {
    static let fallbackScreenID = "main"

    static func id(for screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return String(screenNumber.uint32Value)
        }
        return screen.localizedName.isEmpty ? fallbackScreenID : screen.localizedName
    }

    static func shortID(for id: String) -> String {
        String(id.suffix(4))
    }

    static func descriptors() -> [NotchIslandScreenDescriptor] {
        let screens = NSScreen.screens
        let nameCounts = Dictionary(grouping: screens, by: \.localizedName)
            .mapValues(\.count)

        return screens.map { screen in
            let id = id(for: screen)
            let name = screen.localizedName.isEmpty ? "Display" : screen.localizedName
            let displayName = (nameCounts[screen.localizedName] ?? 0) > 1
                ? "\(name) (\(shortID(for: id)))"
                : name
            return NotchIslandScreenDescriptor(
                id: id,
                displayName: displayName,
                localizedName: name,
                hasPhysicalNotch: screen.safeAreaInsets.top > 0
            )
        }
    }

    static func screen(for id: String) -> NSScreen? {
        NSScreen.screens.first { Self.id(for: $0) == id }
    }

    static func mainScreenID() -> String {
        if let main = NSScreen.main ?? NSScreen.screens.first {
            return id(for: main)
        }
        return fallbackScreenID
    }

    static func pointerScreenID() -> String {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return id(for: screen)
        }
        return mainScreenID()
    }

    static func defaultSelectedScreenIDs(for legacyMode: NotchIslandDisplayMode = .primaryDisplay) -> Set<String> {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [fallbackScreenID] }

        switch legacyMode {
        case .primaryDisplay:
            return [mainScreenID()]
        case .pointerDisplay:
            return [pointerScreenID()]
        case .allDisplays:
            return Set(screens.map(id(for:)))
        }
    }

    static func selectedScreens(for ids: Set<String>) -> [NSScreen] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }
        let selected = screens.filter { ids.contains(id(for: $0)) }
        if !selected.isEmpty {
            return selected
        }
        return [NSScreen.main ?? screens[0]]
    }

    static func primaryRuntimeScreen(from screens: [NSScreen]) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        if let main = NSScreen.main, screens.contains(main) {
            return main
        }
        let selectedIDs = Set(screens.map(id(for:)))
        return NSScreen.screens.first { selectedIDs.contains(id(for: $0)) } ?? screens[0]
    }
}

enum NotchIslandModule: String, CaseIterable, Sendable, Identifiable {
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

    static let defaultEnabled: Set<NotchIslandModule> = [
        .media,
        .stats,
        .clipboard,
        .colorPicker,
        .calendar,
        .shelf,
        .privacy,
        .focus,
        .battery,
        .bluetooth,
        .downloads,
        .osd
    ]

    var id: String { rawValue }

    var title: String { title() }

    func title(locale: Locale? = nil) -> String {
        switch self {
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

    var settingsDescription: String { settingsDescription() }

    func settingsDescription(locale: Locale? = nil) -> String {
        switch self {
        case .media: NotchIslandLocalization.atollText("Atoll media controls, artwork, and playback live activity.", locale: locale)
        case .stats: NotchIslandLocalization.atollText("CPU, memory, disk, network, battery, GPU, and thermal readouts.", locale: locale)
        case .timer: NotchIslandLocalization.atollText("Inline timer controls and timer live activity.", locale: locale)
        case .clipboard: NotchIslandLocalization.atollText("Clipboard history surface and popover entry point.", locale: locale)
        case .colorPicker: NotchIslandLocalization.atollText("Color picker entry point and picked-colour feedback.", locale: locale)
        case .calendar: NotchIslandLocalization.atollText("Calendar and reminder previews near the notch.", locale: locale)
        case .shelf: NotchIslandLocalization.atollText("File shelf, AirDrop, QuickShare, and LocalSend surfaces.", locale: locale)
        case .privacy: NotchIslandLocalization.atollText("Camera and microphone privacy indicators.", locale: locale)
        case .recording: NotchIslandLocalization.atollText("Screen-recording live activity and indicator.", locale: locale)
        case .focus: NotchIslandLocalization.atollText("Do Not Disturb and Focus live activity.", locale: locale)
        case .battery: NotchIslandLocalization.atollText("Battery, charging, and power-source live activity.", locale: locale)
        case .bluetooth: NotchIslandLocalization.atollText("Bluetooth audio device status and connection HUD.", locale: locale)
        case .downloads: NotchIslandLocalization.atollText("Browser download live activity and progress display.", locale: locale)
        case .osd: NotchIslandLocalization.atollText("Volume, brightness, keyboard backlight, and custom HUD overlays.", locale: locale)
        case .lockScreenWidgets: NotchIslandLocalization.atollText("Atoll-style lock-screen panels and widgets.", locale: locale)
        case .extensionBridge: NotchIslandLocalization.atollText("Atoll extension RPC/XPC event bridge.", locale: locale)
        case .screenAssistant: NotchIslandLocalization.atollText("Screen assistant panels, screenshot snipping, and model chooser.", locale: locale)
        }
    }

    var isHeavyOrExperimental: Bool {
        switch self {
        case .media, .stats, .timer, .clipboard, .colorPicker, .calendar, .privacy, .battery:
            false
        case .shelf, .recording, .focus, .bluetooth, .downloads, .osd, .lockScreenWidgets, .extensionBridge, .screenAssistant:
            true
        }
    }

    var atollSourceHint: String {
        switch self {
        case .media: "ThirdParty/Atoll/DynamicIsland/MediaControllers"
        case .stats: "ThirdParty/Atoll/DynamicIsland/components/Stats"
        case .timer: "ThirdParty/Atoll/DynamicIsland/components/Timer"
        case .clipboard: "ThirdParty/Atoll/DynamicIsland/components/Clipboard"
        case .colorPicker: "ThirdParty/Atoll/DynamicIsland/components/ColorPicker"
        case .calendar: "ThirdParty/Atoll/DynamicIsland/components/Calendar"
        case .shelf: "ThirdParty/Atoll/DynamicIsland/components/Shelf"
        case .privacy: "ThirdParty/Atoll/DynamicIsland/components/Privacy"
        case .recording: "ThirdParty/Atoll/DynamicIsland/components/Recording"
        case .focus: "ThirdParty/Atoll/DynamicIsland/components/Focus"
        case .battery: "ThirdParty/Atoll/DynamicIsland/components/Live activities/DynamicIslandBattery.swift"
        case .bluetooth: "ThirdParty/Atoll/DynamicIsland/managers/BluetoothAudioManager.swift"
        case .downloads: "ThirdParty/Atoll/DynamicIsland/components/Downloads"
        case .osd: "ThirdParty/Atoll/DynamicIsland/components/OSD"
        case .lockScreenWidgets: "ThirdParty/Atoll/DynamicIsland/components/LockScreen"
        case .extensionBridge: "ThirdParty/Atoll/DynamicIsland/services/Extensions"
        case .screenAssistant: "ThirdParty/Atoll/DynamicIsland/components/ScreenAssistant"
        }
    }
}

enum NotchIslandPermissionState: Sendable, Equatable {
    case available
    case needsPermission(String)
    case disabledByDefault
    case sourceLinked

    var displayName: String { displayName() }

    func displayName(locale: Locale? = nil) -> String {
        switch self {
        case .available:
            NotchIslandLocalization.atollText("Available", locale: locale)
        case .needsPermission(let permission):
            NotchIslandLocalization.isSimplifiedChinese(locale: locale)
                ? "需要\(permissionName(permission, locale: locale))权限"
                : "Needs \(permission)"
        case .disabledByDefault:
            NotchIslandLocalization.atollText("Off by default", locale: locale)
        case .sourceLinked:
            NotchIslandLocalization.atollText("Source linked", locale: locale)
        }
    }

    private func permissionName(_ permission: String, locale: Locale? = nil) -> String {
        switch permission {
        case "Music / Apple Events": "音乐 / Apple Events"
        case "Calendar": "日历"
        case "Camera / Microphone": "摄像头 / 麦克风"
        case "Screen Recording": "屏幕录制"
        default: permission
        }
    }
}
