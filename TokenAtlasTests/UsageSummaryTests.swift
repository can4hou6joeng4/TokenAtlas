import Testing
import Foundation
@testable import TokenAtlas

@Suite("UsageSummary.makeCustom")
struct UsageSummaryTests {

    private let cal = Calendar.current

    private func tokens(_ n: Int) -> TokenUsage {
        TokenUsage(inputTokens: n, outputTokens: 0, cacheReadTokens: 0,
                   cacheCreation5mTokens: 0, cacheCreation1hTokens: 0)
    }

    /// A session whose activity and single timeline bucket both land on
    /// `dayStart + hour`.
    private func session(_ id: String, daysAgo n: Int, hour: Int, model: String, count: Int) -> Session {
        let dayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -n, to: .now)!)
        let when = cal.date(byAdding: .hour, value: hour, to: dayStart)!
        let stats = SessionStats(
            title: id, messageCount: 1, firstActivity: when, lastActivity: when,
            models: [ModelUsage(model: model, messageCount: 1, usage: tokens(count), pricing: TestPricing.table)],
            timeline: [ModelBucket(model: model, start: when, usage: tokens(count))]
        )
        return Session(id: id, externalID: id, provider: .claude, projectDirectoryName: "-p",
                       filePath: "/\(id).jsonl", cwd: nil, lastModified: when, fileSize: 1, stats: stats)
    }

    private func session(_ id: String, messageCount: Int, models: [ModelUsage]) -> Session {
        let when = Date.now
        let stats = SessionStats(
            title: id,
            messageCount: messageCount,
            firstActivity: when,
            lastActivity: when,
            models: models,
            timeline: []
        )
        return Session(id: id, externalID: id, provider: .claude, projectDirectoryName: "-p",
                       filePath: "/\(id).jsonl", cwd: nil, lastModified: when, fileSize: 1, stats: stats)
    }

    private func legacySession(
        _ id: String,
        daysAgo n: Int,
        hour: Int,
        models: [ModelUsage],
        timeline: [ModelBucket] = []
    ) -> Session {
        let dayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -n, to: .now)!)
        let when = cal.date(byAdding: .hour, value: hour, to: dayStart)!
        let stats = SessionStats(
            title: id,
            messageCount: 1,
            firstActivity: when,
            lastActivity: when,
            models: models,
            timeline: timeline
        )
        return Session(id: id, externalID: id, provider: .claude, projectDirectoryName: "-p",
                       filePath: "/\(id).jsonl", cwd: nil, lastModified: when, fileSize: 1, stats: stats)
    }

    private func model(_ name: String, count: Int) -> ModelUsage {
        ModelUsage(model: name, messageCount: 1, usage: tokens(count), pricing: TestPricing.table)
    }

    @Test("Only sessions inside the [start, end] day range count")
    func filtersByRange() {
        let sessions = [
            session("today", daysAgo: 0, hour: 10, model: "model-a", count: 100),
            session("d2", daysAgo: 2, hour: 10, model: "model-a", count: 200),
            session("d5", daysAgo: 5, hour: 10, model: "model-a", count: 400),
            session("d9", daysAgo: 9, hour: 10, model: "model-a", count: 800),
        ]
        let start = cal.date(byAdding: .day, value: -5, to: .now)!
        let end = cal.date(byAdding: .day, value: -1, to: .now)!   // excludes "today" and "d9"
        let summary = UsageSummary.makeCustom(start: start, end: end, sessions: sessions, pricing: TestPricing.table)

        #expect(summary.sessionCount == 2)            // d2 + d5
        #expect(summary.totalTokens == 600)
        #expect(summary.timeline.count == 2)
    }

    @Test("End day is inclusive")
    func endDayInclusive() {
        let sessions = [session("d3", daysAgo: 3, hour: 23, model: "model-a", count: 50)]
        let day = cal.date(byAdding: .day, value: -3, to: .now)!
        let summary = UsageSummary.makeCustom(start: day, end: day, sessions: sessions, pricing: TestPricing.table)
        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 50)
    }

    @Test("Custom-range summaries chart at daily granularity")
    func dailyGranularity() {
        let sessions = [
            session("d1", daysAgo: 1, hour: 9, model: "model-a", count: 10),
            session("d3", daysAgo: 3, hour: 9, model: "model-a", count: 20),
        ]
        let start = cal.date(byAdding: .day, value: -4, to: .now)!
        let summary = UsageSummary.makeCustom(start: start, end: .now, sessions: sessions, pricing: TestPricing.table)
        #expect(summary.trendSeries().granularity == .day)
    }

    @Test("Message counts come from session stats instead of model rows")
    func messageCountUsesSessionStats() {
        let visibleModel = ModelUsage(model: "model-a", messageCount: 1, usage: tokens(10), pricing: TestPricing.table)
        let summary = UsageSummary.make(period: .allTime, sessions: [
            session("synthetic-filtered", messageCount: 3, models: [visibleModel]),
        ], pricing: TestPricing.table)

        #expect(summary.messageCount == 3)
        #expect(summary.models.first?.messageCount == 1)
    }

    @Test("Total cost can be read by selected estimate mode")
    func totalCostByMode() {
        let model = ModelUsage(
            model: "model-a",
            messageCount: 1,
            usage: tokens(10),
            costEstimate: CostEstimate(standardAPI: 1.25, detailedBilling: 3.5)
        )
        let summary = UsageSummary.make(period: .allTime, sessions: [
            session("cost-mode", messageCount: 1, models: [model]),
        ], pricing: TestPricing.table)

        #expect(summary.totalCost(for: .standardAPI) == 1.25)
        #expect(summary.totalCost(for: .detailedBilling) == 3.5)
    }

    @Test("Legacy sessions without timeline generate fallback trend buckets")
    func legacySessionsWithoutTimelineGenerateFallbackBuckets() {
        let sessions = [
            legacySession("legacy", daysAgo: 1, hour: 13, models: [
                model("model-a", count: 100),
                model("model-b", count: 250),
            ]),
        ]

        let summary = UsageSummary.make(period: .allTime, sessions: sessions, pricing: TestPricing.table)
        let expectedStart = cal.dateInterval(of: .hour, for: sessions[0].lastModified)!.start
        let series = summary.trendSeries()

        #expect(summary.timeline.count == 2)
        #expect(Set(summary.timeline.map(\.start)) == [expectedStart])
        #expect(summary.timeline.totalTokens == 350)
        #expect(series.models == ["model-b", "model-a"])
        #expect(series.isEmpty == false)
    }

    @Test("Fallback buckets follow selected period filters")
    func fallbackBucketsFollowSelectedPeriodFilters() {
        let sessions = [
            legacySession("today", daysAgo: 0, hour: 1, models: [model("model-a", count: 120)]),
            legacySession("old", daysAgo: 2, hour: 1, models: [model("model-a", count: 900)]),
        ]

        let summary = UsageSummary.make(period: .today, sessions: sessions, pricing: TestPricing.table)

        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 120)
        #expect(summary.timeline.totalTokens == 120)
        #expect(summary.trendSeries().isEmpty == false)
    }

    @Test("Fallback buckets follow custom range filters")
    func fallbackBucketsFollowCustomRangeFilters() {
        let sessions = [
            legacySession("inside", daysAgo: 3, hour: 1, models: [model("model-a", count: 120)]),
            legacySession("outside", daysAgo: 9, hour: 1, models: [model("model-a", count: 900)]),
        ]
        let start = cal.date(byAdding: .day, value: -4, to: .now)!
        let end = cal.date(byAdding: .day, value: -2, to: .now)!

        let summary = UsageSummary.makeCustom(start: start, end: end, sessions: sessions, pricing: TestPricing.table)

        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 120)
        #expect(summary.timeline.totalTokens == 120)
        #expect(summary.trendSeries().isEmpty == false)
    }

    @Test("Today summary clips timeline tokens inside cross-day sessions")
    func todaySummaryClipsTimelineTokensInsideCrossDaySessions() {
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let yesterdayBucket = cal.date(byAdding: .hour, value: 23, to: yesterday)!
        let todayBucket = cal.date(byAdding: .hour, value: 1, to: today)!
        let stats = SessionStats(
            title: "cross-day",
            messageCount: 2,
            firstActivity: yesterdayBucket,
            lastActivity: todayBucket,
            models: [model("model-a", count: 1_000)],
            timeline: [
                ModelBucket(model: "model-a", start: yesterdayBucket, usage: tokens(900)),
                ModelBucket(model: "model-a", start: todayBucket, usage: tokens(100)),
            ]
        )
        let session = Session(
            id: "cross-day",
            externalID: "cross-day",
            provider: .codex,
            projectDirectoryName: "-p",
            filePath: "/cross-day.jsonl",
            cwd: nil,
            lastModified: todayBucket,
            fileSize: 1,
            stats: stats
        )

        let summary = UsageSummary.make(period: .today, sessions: [session], pricing: TestPricing.table)

        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 100)
        #expect(summary.timeline.totalTokens == 100)
        #expect(summary.models.first?.usage.total == 100)
    }

    @Test("Today summary excludes future dated timeline buckets")
    func todaySummaryExcludesFutureDatedTimelineBuckets() {
        let today = cal.startOfDay(for: .now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let todayBucket = cal.date(byAdding: .hour, value: 1, to: today)!
        let tomorrowBucket = cal.date(byAdding: .hour, value: 1, to: tomorrow)!
        let stats = SessionStats(
            title: "future-dated",
            messageCount: 2,
            firstActivity: todayBucket,
            lastActivity: tomorrowBucket,
            models: [model("model-a", count: 1_000)],
            timeline: [
                ModelBucket(model: "model-a", start: todayBucket, usage: tokens(100)),
                ModelBucket(model: "model-a", start: tomorrowBucket, usage: tokens(900)),
            ]
        )
        let session = Session(
            id: "future-dated",
            externalID: "future-dated",
            provider: .codex,
            projectDirectoryName: "-p",
            filePath: "/future-dated.jsonl",
            cwd: nil,
            lastModified: tomorrowBucket,
            fileSize: 1,
            stats: stats
        )

        let summary = UsageSummary.make(period: .today, sessions: [session], pricing: TestPricing.table)

        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 100)
        #expect(summary.timeline.totalTokens == 100)
    }

    @Test("Today summary excludes cross-day sessions with no today token buckets")
    func todaySummaryExcludesCrossDaySessionsWithNoTodayTokenBuckets() {
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let yesterdayBucket = cal.date(byAdding: .hour, value: 23, to: yesterday)!
        let todayActivity = cal.date(byAdding: .hour, value: 1, to: today)!
        let stats = SessionStats(
            title: "stale-cross-day",
            messageCount: 2,
            firstActivity: yesterdayBucket,
            lastActivity: todayActivity,
            models: [model("model-a", count: 900)],
            timeline: [
                ModelBucket(model: "model-a", start: yesterdayBucket, usage: tokens(900)),
            ]
        )
        let session = Session(
            id: "stale-cross-day",
            externalID: "stale-cross-day",
            provider: .codex,
            projectDirectoryName: "-p",
            filePath: "/stale-cross-day.jsonl",
            cwd: nil,
            lastModified: todayActivity,
            fileSize: 1,
            stats: stats
        )

        let summary = UsageSummary.make(period: .today, sessions: [session], pricing: TestPricing.table)

        #expect(summary.sessionCount == 0)
        #expect(summary.totalTokens == 0)
        #expect(summary.timeline.isEmpty)
    }

    @Test("Subagent turns that appear in both parent and child sessions are deduped by message hash")
    func dedupesSubagentTurnsByHash() {
        // Simulate Claude Code's Task tool: the same assistant turn (same
        // message.id + requestId) shows up in both the parent session's
        // JSONL and the subagent's. Without dedup, aggregate cost would be
        // counted twice.
        let when = cal.date(byAdding: .hour, value: -1, to: .now)!
        let cost = CostEstimate(standardAPI: 0.50)
        let sharedTurn = BillableMessage(
            hash: "msg_subagent:req_abc",
            model: "model-a",
            usage: tokens(1_000),
            cost: cost,
            timestamp: when
        )
        let parentOnly = BillableMessage(
            hash: "msg_parent:req_xyz",
            model: "model-a",
            usage: tokens(500),
            cost: CostEstimate(standardAPI: 0.25),
            timestamp: when
        )

        func sessionWith(_ id: String, _ msgs: [BillableMessage]) -> Session {
            let modelUsage = ModelUsage(
                model: "model-a",
                messageCount: msgs.count,
                usage: msgs.reduce(.zero) { $0 + $1.usage },
                costEstimate: msgs.reduce(.zero) { $0 + $1.cost }
            )
            let stats = SessionStats(
                title: id, messageCount: msgs.count,
                firstActivity: when, lastActivity: when,
                models: [modelUsage], timeline: [],
                billableMessages: msgs
            )
            return Session(id: id, externalID: id, provider: .claude,
                           projectDirectoryName: "-p", filePath: "/\(id).jsonl",
                           cwd: nil, lastModified: when, fileSize: 1, stats: stats)
        }

        let summary = UsageSummary.make(period: .allTime, sessions: [
            sessionWith("parent", [parentOnly, sharedTurn]),
            sessionWith("subagent", [sharedTurn]),
        ], pricing: TestPricing.table)

        // 1500 = parentOnly(500) + sharedTurn(1000) counted ONCE
        #expect(summary.totalTokens == 1_500)
        #expect(abs(summary.totalCost(for: .standardAPI) - 0.75) < 1e-9)
        // Models row reflects the deduped message count (2, not 3).
        #expect(summary.models.first?.messageCount == 2)
    }

    @Test("Existing timeline is not double counted by model fallback")
    func existingTimelineIsNotDoubleCounted() {
        let bucketStart = cal.date(byAdding: .hour, value: 9, to: cal.startOfDay(for: .now))!
        let sessions = [
            legacySession(
                "timeline",
                daysAgo: 0,
                hour: 10,
                models: [model("model-a", count: 999)],
                timeline: [ModelBucket(model: "model-a", start: bucketStart, usage: tokens(100))]
            ),
        ]

        let summary = UsageSummary.make(period: .allTime, sessions: sessions, pricing: TestPricing.table)

        #expect(summary.totalTokens == 999)
        #expect(summary.timeline.count == 1)
        #expect(summary.timeline.totalTokens == 100)
    }

    @MainActor
    @Test("Usage derived data is keyed by data inputs, not layout")
    func usageDerivedDataKeyedByDataInputs() {
        let store = SessionStore(registry: ProviderRegistry(pricing: TestPricing.table), pricing: TestPricing.table)
        store.loadPreviewSessions([
            session("derived", daysAgo: 0, hour: 10, model: "model-a", count: 120),
        ])

        let key = UsageDerivedData.Key(
            period: .allTime,
            provider: .claude,
            lastRefreshedAt: store.lastRefreshedAt
        )
        let snapshot = UsageDerivedData.make(key: key, store: store)

        #expect(snapshot.summary.totalTokens == 120)
        #expect(snapshot.series.models == ["model-a"])
        #expect(key == UsageDerivedData.Key(period: .allTime, provider: .claude, lastRefreshedAt: store.lastRefreshedAt))
        #expect(key != UsageDerivedData.Key(period: .last7Days, provider: .claude, lastRefreshedAt: store.lastRefreshedAt))
        #expect(key != UsageDerivedData.Key(period: .allTime, provider: .codex, lastRefreshedAt: store.lastRefreshedAt))
    }

    @MainActor
    @Test("Trend snapshot key changes when empty derived data is replaced by real data")
    func trendSnapshotKeyIncludesSeriesRevision() {
        let store = SessionStore(registry: ProviderRegistry(pricing: TestPricing.table), pricing: TestPricing.table)
        store.loadPreviewSessions([
            legacySession("real-trend", daysAgo: 0, hour: 10, models: [model("model-a", count: 120)]),
        ])
        let key = UsageDerivedData.Key(
            period: .allTime,
            provider: .claude,
            lastRefreshedAt: store.lastRefreshedAt
        )
        let empty = UsageDerivedData.empty(for: key)
        let real = UsageDerivedData.make(key: key, store: store)

        let emptyKey = UsageTrendSnapshotKey(
            seriesID: key.chartSeriesID,
            rangeID: key.period.rawValue,
            style: .line,
            useLog: false,
            stackByType: false,
            seriesRevisionID: empty.series.dataRevisionID
        )
        let realKey = UsageTrendSnapshotKey(
            seriesID: key.chartSeriesID,
            rangeID: key.period.rawValue,
            style: .line,
            useLog: false,
            stackByType: false,
            seriesRevisionID: real.series.dataRevisionID
        )

        #expect(empty.key.chartSeriesID == real.key.chartSeriesID)
        #expect(emptyKey != realKey)
    }

    @MainActor
    @Test("Model breakdown key changes when empty derived data is replaced by real data")
    func modelBreakdownKeyIncludesDataRevisions() {
        let store = SessionStore(registry: ProviderRegistry(pricing: TestPricing.table), pricing: TestPricing.table)
        store.loadPreviewSessions([
            legacySession("real-models", daysAgo: 0, hour: 10, models: [model("model-a", count: 120)]),
        ])
        let key = UsageDerivedData.Key(
            period: .allTime,
            provider: .claude,
            lastRefreshedAt: store.lastRefreshedAt
        )
        let empty = UsageDerivedData.empty(for: key)
        let real = UsageDerivedData.make(key: key, store: store)

        let emptyKey = UsageModelBreakdownSnapshot.Key(
            seriesID: key.chartSeriesID,
            includeCacheInTokens: true,
            costEstimationMode: .standardAPI,
            modelsRevisionID: empty.summary.models.dataRevisionID,
            seriesRevisionID: empty.series.dataRevisionID
        )
        let realKey = UsageModelBreakdownSnapshot.Key(
            seriesID: key.chartSeriesID,
            includeCacheInTokens: true,
            costEstimationMode: .standardAPI,
            modelsRevisionID: real.summary.models.dataRevisionID,
            seriesRevisionID: real.series.dataRevisionID
        )

        #expect(empty.key.chartSeriesID == real.key.chartSeriesID)
        #expect(emptyKey != realKey)
    }

    @MainActor
    @Test("Usage derived data and model breakdown handle legacy sessions without timeline")
    func usageDerivedDataHandlesLegacySessionsWithoutTimeline() {
        let store = SessionStore(registry: ProviderRegistry(pricing: TestPricing.table), pricing: TestPricing.table)
        store.loadPreviewSessions([
            legacySession("legacy-derived", daysAgo: 0, hour: 10, models: [model("model-a", count: 120)]),
        ])
        let key = UsageDerivedData.Key(
            period: .allTime,
            provider: .claude,
            lastRefreshedAt: store.lastRefreshedAt
        )

        let data = UsageDerivedData.make(key: key, store: store)
        let breakdown = UsageModelBreakdownSnapshot(
            key: UsageModelBreakdownSnapshot.Key(
                seriesID: data.key.chartSeriesID,
                includeCacheInTokens: true,
                costEstimationMode: .standardAPI,
                modelsRevisionID: data.summary.models.dataRevisionID,
                seriesRevisionID: data.series.dataRevisionID
            ),
            models: data.summary.models,
            series: data.series,
            displayName: { $0 }
        )

        #expect(data.summary.totalTokens == 120)
        #expect(data.series.models == ["model-a"])
        #expect(data.series.isEmpty == false)
        #expect(breakdown.rows.map(\.id) == ["model-a"])
    }

    @Test("Model breakdown snapshot summarizes solid and cached model tokens")
    func modelBreakdownSnapshotSummarizesModelTokenKinds() {
        let models = [
            ModelUsage(
                model: "model-a",
                messageCount: 2,
                usage: TokenUsage(
                    inputTokens: 100,
                    outputTokens: 20,
                    cacheReadTokens: 300,
                    cacheCreation5mTokens: 10
                ),
                estimatedCost: 1.25
            ),
            ModelUsage(
                model: "model-b",
                messageCount: 1,
                usage: TokenUsage(inputTokens: 50, outputTokens: 10),
                estimatedCost: 0.25
            ),
        ]
        let series = TrendSeries(granularity: .day, models: ["model-a", "model-b"], buckets: [])

        let includingCache = UsageModelBreakdownSnapshot(
            key: UsageModelBreakdownSnapshot.Key(
                seriesID: "series",
                includeCacheInTokens: true,
                costEstimationMode: .standardAPI,
                modelsRevisionID: models.dataRevisionID,
                seriesRevisionID: series.dataRevisionID
            ),
            models: models,
            series: series,
            displayName: { $0 }
        )
        let excludingCache = UsageModelBreakdownSnapshot(
            key: UsageModelBreakdownSnapshot.Key(
                seriesID: "series",
                includeCacheInTokens: false,
                costEstimationMode: .standardAPI,
                modelsRevisionID: models.dataRevisionID,
                seriesRevisionID: series.dataRevisionID
            ),
            models: models,
            series: series,
            displayName: { $0 }
        )

        #expect(includingCache.totalTokens == 490)
        #expect(includingCache.solidTokens == 190)
        #expect(includingCache.cacheReadTokens == 300)
        #expect(includingCache.rows.map(\.totalTokens) == [430, 60])
        #expect(includingCache.rows.map(\.cacheReadTokens) == [300, 0])
        #expect(excludingCache.totalTokens == 190)
        #expect(excludingCache.solidTokens == 190)
        #expect(excludingCache.cacheReadTokens == 0)
        #expect(excludingCache.rows.map(\.totalTokens) == [130, 60])
    }
}
