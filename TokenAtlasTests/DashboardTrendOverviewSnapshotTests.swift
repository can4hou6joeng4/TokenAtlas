import Foundation
import Testing
@testable import TokenAtlas

@Suite("DashboardTrendOverviewSnapshot")
struct DashboardTrendOverviewSnapshotTests {
    @Test("Aggregates model buckets into visible daily totals")
    func aggregatesDailyTotals() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day0 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let day1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let series = TrendSeries(
            granularity: .day,
            models: ["model-a", "model-b"],
            buckets: [
                ModelBucket(model: "model-a", start: day0, usage: TokenUsage(inputTokens: 100)),
                ModelBucket(model: "model-b", start: day0, usage: TokenUsage(outputTokens: 50)),
                ModelBucket(model: "model-a", start: day1, usage: TokenUsage(cacheReadTokens: 25)),
            ]
        )

        let snapshot = DashboardTrendOverviewSnapshot(
            key: DashboardTrendOverviewSnapshot.Key(seriesID: "daily", seriesRevisionID: series.dataRevisionID),
            series: series
        )

        #expect(snapshot.buckets.map(\.date) == [day0, day1])
        #expect(snapshot.buckets.map(\.tokens) == [150, 25])
        #expect(snapshot.totalTokens == 175)
        #expect(snapshot.activeBucketCount == 2)
        #expect(snapshot.averageTokensPerActiveBucket == 87)
        #expect(snapshot.peakBucket?.date == day0)
        #expect(snapshot.yMax == DashboardTrendOverviewSnapshot.niceCeiling(150))
        #expect(snapshot.yTicks.count == DashboardTrendOverviewSnapshot.yTickCount + 1)
        #expect(snapshot.xLabelIndices == Set([0, 1]))
        #expect(snapshot.isEmpty == false)
    }

    @Test("Treats zero-filled series as empty while preserving bucket count")
    func zeroFilledSeriesIsEmpty() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let series = TrendSeries(
            granularity: .day,
            models: ["model-a"],
            buckets: [
                ModelBucket(model: "model-a", start: day, usage: .zero),
            ]
        )

        let snapshot = DashboardTrendOverviewSnapshot(
            key: DashboardTrendOverviewSnapshot.Key(seriesID: "zero", seriesRevisionID: series.dataRevisionID),
            series: series
        )

        #expect(snapshot.buckets.count == 1)
        #expect(snapshot.totalTokens == 0)
        #expect(snapshot.activeBucketCount == 0)
        #expect(snapshot.averageTokensPerActiveBucket == 0)
        #expect(snapshot.isEmpty)
    }

    @Test("Samples dense labels while keeping lightweight trend axis ticks")
    func denseSeriesSamplesLabelsAndTicks() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let buckets = try (0..<30).map { offset in
            let day = try #require(calendar.date(byAdding: .day, value: offset, to: start))
            return ModelBucket(model: "model-a", start: day, usage: TokenUsage(inputTokens: (offset + 1) * 1_000))
        }
        let series = TrendSeries(granularity: .day, models: ["model-a"], buckets: buckets)

        let snapshot = DashboardTrendOverviewSnapshot(
            key: DashboardTrendOverviewSnapshot.Key(seriesID: "dense", seriesRevisionID: series.dataRevisionID),
            series: series
        )

        #expect(snapshot.buckets.count == 30)
        #expect(snapshot.yTicks == [50_000, 37_500, 25_000, 12_500, 0])
        #expect(snapshot.xLabelIndices.count == 8)
        #expect(snapshot.xLabelIndices.contains(0))
        #expect(snapshot.xLabelIndices.contains(29))
    }
}
