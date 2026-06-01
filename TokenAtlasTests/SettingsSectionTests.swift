import Testing
@testable import TokenAtlas

@Suite("SettingsSection")
struct SettingsSectionTests {

    @Test("Analysis terms remain routable but hidden from the primary settings sidebar")
    func analysisTermsRouteIsHiddenFromSidebar() {
        #expect(SettingsSection(rawValue: "dictionary") == .dictionary)
        #expect(SettingsSection.dictionary.title == "Analysis Terms")
        #expect(!SettingsSection.dictionary.isVisibleInSidebar)
        #expect(!SettingsSection.visibleSidebarSections.contains(.dictionary))
        #expect(SettingsSection.visibleSidebarSections.contains(.general))
    }
}
