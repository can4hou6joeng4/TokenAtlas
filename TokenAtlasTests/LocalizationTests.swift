import Foundation
import Testing
@testable import TokenAtlas

@Suite("Localization")
@MainActor
struct LocalizationTests {
    @Test("App language preference persists and updates app language defaults")
    func appLanguagePreferencePersists() {
        let (defaults, suiteName) = makeDefaults()
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.appLanguagePreference == .system)
        #expect(appLanguageOverride(in: defaults, suiteName: suiteName) == nil)

        prefs.appLanguagePreference = .simplifiedChinese
        #expect(defaults.string(forKey: "appLanguagePreference") == AppLanguagePreference.simplifiedChinese.rawValue)
        #expect(appLanguageOverride(in: defaults, suiteName: suiteName) == ["zh-Hans"])

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.appLanguagePreference == .simplifiedChinese)
        #expect(appLanguageOverride(in: defaults, suiteName: suiteName) == ["zh-Hans"])

        reloaded.appLanguagePreference = .system
        #expect(appLanguageOverride(in: defaults, suiteName: suiteName) == nil)
    }

    @Test("Language metadata exposes expected locale identifiers and labels")
    func appLanguagePreferenceMetadata() {
        #expect(AppLanguagePreference.system.localeIdentifier == nil)
        #expect(AppLanguagePreference.english.localeIdentifier == "en")
        #expect(AppLanguagePreference.simplifiedChinese.localeIdentifier == "zh-Hans")
        #expect(AppLanguagePreference.system.displayName(locale: Locale(identifier: "en")) == "Follow System")
        #expect(AppLanguagePreference.system.displayName(locale: Locale(identifier: "zh-Hans")) == "跟随系统")
        #expect(AppLanguagePreference.simplifiedChinese.displayName(locale: Locale(identifier: "en")) == "简体中文")
    }

    @Test("Dynamic localized strings handle plural and interpolation differences")
    func dynamicLocalizedStrings() {
        let en = Locale(identifier: "en")
        let zh = Locale(identifier: "zh-Hans")

        #expect(L10n.refreshInterval(minutes: 1, locale: en) == "1 minute")
        #expect(L10n.refreshInterval(minutes: 5, locale: en) == "5 minutes")
        #expect(L10n.refreshInterval(minutes: 1, locale: zh) == "1 分钟")
        #expect(L10n.refreshInterval(minutes: 5, locale: zh) == "5 分钟")
        #expect(L10n.contributionCount(2, locale: zh) == "2 次贡献")
        #expect(L10n.format("stats.header.provider_stats", defaultValue: "%@ STATS", locale: zh, "Claude") == "Claude 统计")
    }

    @Test("Sessions overview and analysis labels have Chinese localizations")
    func sessionsLabelsHaveChineseLocalizations() {
        let zh = Locale(identifier: "zh-Hans")

        #expect(L10n.string("sessions.sidebar.overview", defaultValue: "Overview", locale: zh) == "概览")
        #expect(L10n.string("sessions.sidebar.analysis", defaultValue: "Analysis", locale: zh) == "分析")
        #expect(L10n.string("sessions.overview.stat.sessions", defaultValue: "SESSIONS", locale: zh) == "会话数")
        #expect(L10n.string("sessions.overview.stat.total_tokens", defaultValue: "TOTAL TOKENS", locale: zh) == "总令牌")
        #expect(L10n.string("sessions.analysis.stat.analyzed", defaultValue: "ANALYZED", locale: zh) == "已分析")
        #expect(L10n.string("sessions.analysis.edit_terms", defaultValue: "Edit Terms", locale: zh) == "编辑术语")
        #expect(L10n.string("sessions.analysis.filter.all", defaultValue: "All", locale: zh) == "全部")
        #expect(L10n.format("sessions.analysis.term.metrics",
                            defaultValue: "freq %d - sessions %d - score %@",
                            locale: zh,
                            12,
                            3,
                            "4.5") == "频次 12 - 会话 3 - 分数 4.5")
    }

    @Test("Transcript analysis display names are localized")
    func transcriptAnalysisDisplayNamesAreLocalized() {
        let zh = Locale(identifier: "zh-Hans")

        #expect(L10n.string("analysis.term.kind.language", defaultValue: "Language", locale: zh) == "语言")
        #expect(L10n.string("analysis.term.kind.file", defaultValue: "File", locale: zh) == "文件")
        #expect(L10n.string("analysis.term.kind.workflow", defaultValue: "Workflow", locale: zh) == "流程")
        #expect(L10n.string("analysis.progress.analyzing_transcripts",
                            defaultValue: "Analyzing transcripts",
                            locale: zh) == "正在分析对话")
    }

    @Test("Notch Island settings labels are localized")
    func notchIslandSettingsLabelsAreLocalized() {
        let zh = Locale(identifier: "zh-Hans")

        #expect(NotchIslandSettingsTab.island.title(locale: zh) == "刘海岛")
        #expect(NotchIslandSettingsTab.appearance.title(locale: zh) == "外观")
        #expect(NotchIslandSettingsGroup.live.title(locale: zh) == "实时")
        #expect(NotchIslandSettingsGroup.utilities.title(locale: zh) == "工具")
        #expect(NotchIslandSizePreset.regular.displayName(locale: zh) == "标准")
        #expect(NotchIslandScreenStyle.sameAsNotch.displayName(locale: zh) == "跟随刘海")
        #expect(NotchIslandScreenStyle.sameAsNotch.description(locale: zh) == "融入屏幕顶部边缘。")
        #expect(NotchIslandModule.media.title(locale: zh) == "媒体")
        #expect(NotchIslandPermissionState.disabledByDefault.displayName(locale: zh) == "默认关闭")
        #expect(NotchIslandLocalization.atollText("Preview", locale: zh) == "预览")
        #expect(NotchIslandLocalization.atollText("Disabled", locale: zh) == "已关闭")
        #expect(NotchIslandLocalization.atollText("Enabled", locale: zh) == "已开启")
        #expect(NotchIslandLocalization.atollText("Off", locale: zh) == "关闭")
    }

    @Test("Typography chooses Sora for English and system font for Chinese")
    func typographyLanguageSelection() {
        #expect(Theme.appFontKind(for: Locale(identifier: "en")) == .sora)
        #expect(Theme.appFontKind(for: Locale(identifier: "en_US")) == .sora)
        #expect(Theme.appFontKind(for: Locale(identifier: "zh-Hans")) == .system)
        #expect(Theme.appFontKind(forLanguageIdentifier: "zh_CN") == .system)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "com.tokenatlas.localization.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func appLanguageOverride(in defaults: UserDefaults, suiteName: String) -> [String]? {
        defaults.persistentDomain(forName: suiteName)?[AppLanguagePreference.appleLanguagesDefaultsKey] as? [String]
    }
}
