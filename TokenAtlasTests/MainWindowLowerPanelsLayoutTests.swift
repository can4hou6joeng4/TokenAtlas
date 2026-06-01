import CoreGraphics
import Testing
@testable import TokenAtlas

@Suite("MainWindowLowerPanelsWidthPolicy")
struct MainWindowLowerPanelsWidthPolicyTests {
    @Test("trailing fixed policy preserves the trailing column")
    func trailingFixedPolicy() throws {
        let policy = MainWindowLowerPanelsWidthPolicy.trailingFixed(width: 300, leadingMinimumWidth: 560)
        let columns = try #require(policy.columnWidths(for: 980, spacing: 12))

        #expect(columns.leading == 668)
        #expect(columns.trailing == 300)
        #expect(policy.columnWidths(for: 871, spacing: 12) == nil)
    }

    @Test("leading fixed policy preserves the leading column")
    func leadingFixedPolicy() throws {
        let policy = MainWindowLowerPanelsWidthPolicy.leadingFixed(width: 440, trailingMinimumWidth: 420)
        let columns = try #require(policy.columnWidths(for: 980, spacing: 12))

        #expect(columns.leading == 440)
        #expect(columns.trailing == 528)
        #expect(policy.columnWidths(for: 871, spacing: 12) == nil)
    }
}
