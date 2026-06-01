import Foundation
import Testing
@testable import TokenAtlas

@Suite("Release History Catalog")
struct ReleaseHistoryCatalogTests {
    @Test("Entries describe the reset product baseline")
    func entriesCoverReleaseHistory() {
        let entries = ReleaseHistoryCatalog.entries

        #expect(entries.count == 1)
        #expect(entries.first?.version == Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        #expect(entries.first?.version == "1.0.0")
        #expect(entries.first?.headline == "重新定位为精简后的新产品起点")
        #expect(Set(entries.map(\.id)).count == entries.count)
        #expect(entries.allSatisfy { entry in
            !entry.headline.isEmpty
                && !entry.changes.isEmpty
                && entry.changes.allSatisfy { !$0.isEmpty }
        })
    }
}
