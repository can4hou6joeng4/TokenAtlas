import Foundation
import Testing
@testable import TokenAtlas

struct LocalInsightsSnapshotTests {
    @Test
    func aggregatesProviderScopedRecordsAndProjects() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = date("2026-05-25T12:00:00Z")
        let sessions = [
            session(
                provider: .claude,
                project: "alpha",
                lastActivity: date("2026-05-25T10:00:00Z"),
                tokens: 100,
                messages: 3,
                model: "claude-opus"
            ),
            session(
                provider: .claude,
                project: "alpha",
                lastActivity: date("2026-05-20T10:00:00Z"),
                tokens: 60,
                messages: 2,
                model: "claude-sonnet"
            ),
            session(
                provider: .claude,
                project: "beta",
                lastActivity: date("2026-04-20T10:00:00Z"),
                tokens: 300,
                messages: 1,
                model: "claude-haiku"
            ),
            session(
                provider: .codex,
                project: "codex-only",
                lastActivity: date("2026-05-25T11:00:00Z"),
                tokens: 900,
                messages: 9,
                model: "gpt-5"
            ),
        ]

        let snapshot = LocalInsightsSnapshot.make(
            provider: .claude,
            sessions: sessions,
            currentPeriod: .last30Days,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.currentPeriod.sessionCount == 2)
        #expect(snapshot.currentPeriod.totalTokens == 160)
        #expect(snapshot.activeDaysLast30 == 2)
        #expect(snapshot.bestDayTokensLast30 == 100)
        #expect(snapshot.topProjects.map(\.name) == ["beta", "alpha"])

        let allTime = try #require(snapshot.records.first { $0.period == .allTime })
        #expect(allTime.sessions == 3)
        #expect(allTime.tokens == 460)

        let today = try #require(snapshot.records.first { $0.period == .today })
        #expect(today.sessions == 1)
        #expect(today.tokens == 100)
        #expect(today.topModel == "claude-opus")
    }

    private func session(
        provider: ProviderKind,
        project: String,
        lastActivity: Date,
        tokens: Int,
        messages: Int,
        model: String
    ) -> Session {
        let usage = TokenUsage(inputTokens: tokens / 2, outputTokens: tokens - (tokens / 2))
        return Session(
            id: "\(provider.rawValue)-\(project)-\(lastActivity.timeIntervalSinceReferenceDate)",
            externalID: UUID().uuidString,
            provider: provider,
            projectDirectoryName: "-tmp-\(project)",
            filePath: "/tmp/\(project).jsonl",
            cwd: "/tmp/\(project)",
            lastModified: lastActivity,
            fileSize: 1024,
            stats: SessionStats(
                title: project,
                messageCount: messages,
                firstActivity: lastActivity,
                lastActivity: lastActivity,
                models: [
                    ModelUsage(
                        model: model,
                        messageCount: messages,
                        usage: usage,
                        costEstimate: .zero
                    ),
                ],
                timeline: [
                    ModelBucket(model: model, start: lastActivity, usage: usage),
                ]
            )
        )
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}
