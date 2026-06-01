import Foundation

/// Aggregate usage across many sessions, scoped to a ``StatsPeriod``.
struct UsageSummary: Sendable, Hashable {
    let period: StatsPeriod
    let sessionCount: Int
    let models: [ModelUsage]
    let messageCount: Int
    /// Hourly per-model buckets for the sessions counted in this period.
    let timeline: [ModelBucket]

    var totalUsage: TokenUsage { models.reduce(.zero) { $0 + $1.usage } }
    var totalTokens: Int { totalUsage.total }
    var totalCost: Double { totalCost(for: .standardAPI) }

    func totalTokens(includingCacheRead: Bool) -> Int {
        totalUsage.total(includingCacheRead: includingCacheRead)
    }

    func totalCost(for mode: CostEstimationMode) -> Double {
        models.reduce(0) { $0 + $1.estimatedCost(for: mode) }
    }

    static func empty(period: StatsPeriod) -> UsageSummary {
        UsageSummary(period: period, sessionCount: 0, models: [], messageCount: 0, timeline: [])
    }

    /// Build a summary from already-parsed sessions.
    ///
    /// Sessions with per-turn or hourly usage are scoped by the usage event's
    /// timestamp, so a long-running session that crosses midnight does not
    /// contribute yesterday's tokens to today's menu-bar or dashboard totals.
    /// Older sessions without a timeline fall back to whole-session attribution
    /// by last activity.
    static func make(
        period: StatsPeriod,
        sessions: [Session],
        pricing: ModelPricing,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> UsageSummary {
        let scope = UsageScope(
            isUnbounded: period == .allTime,
            contains: { date in
                period.contains(date, now: now, calendar: calendar)
            }
        )
        let aggregate = scopedAggregate(
            sessions: sessions,
            pricing: pricing,
            calendar: calendar,
            scope: scope
        )
        return UsageSummary(
            period: period,
            sessionCount: aggregate.sessionCount,
            models: aggregate.models,
            messageCount: aggregate.messageCount,
            timeline: aggregate.timeline
        )
    }

    /// Build a summary scoped to an explicit `[start, end]` range of calendar
    /// days (inclusive on both ends). The stored `period` is set to
    /// ``StatsPeriod/allTime`` purely so ``trendSeries(now:calendar:)`` picks
    /// daily granularity — the human-facing range label always comes from the
    /// originating ``PeriodSelection``, never from `period`.
    static func makeCustom(start: Date, end: Date, sessions: [Session], pricing: ModelPricing, calendar: Calendar = .current) -> UsageSummary {
        let lo = calendar.startOfDay(for: min(start, end))
        guard let hiExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end))) else {
            return .empty(period: .allTime)
        }
        let scope = UsageScope(isUnbounded: false) { date in
            date >= lo && date < hiExclusive
        }
        let aggregate = scopedAggregate(
            sessions: sessions,
            pricing: pricing,
            calendar: calendar,
            scope: scope
        )
        return UsageSummary(
            period: .allTime,
            sessionCount: aggregate.sessionCount,
            models: aggregate.models,
            messageCount: aggregate.messageCount,
            timeline: aggregate.timeline
        )
    }

    private struct UsageScope {
        let isUnbounded: Bool
        let contains: (Date) -> Bool
    }

    private struct AggregateResult {
        let sessionCount: Int
        let models: [ModelUsage]
        let messageCount: Int
        let timeline: [ModelBucket]
    }

    /// Walk `sessions` and aggregate per-model token totals, cost, and the
    /// hourly timeline for the requested time scope. When a session carries
    /// ``SessionStats/billableMessages`` (a Claude transcript), dedup turns by
    /// `(message.id, requestId)` across every session in this call. Sessions
    /// without billable messages but with a timeline are clipped by bucket.
    /// Legacy sessions without a timeline fall back to whole-session
    /// attribution by last activity.
    private static func scopedAggregate(
        sessions: [Session],
        pricing: ModelPricing,
        calendar: Calendar,
        scope: UsageScope
    ) -> AggregateResult {
        var perModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        var perModelHourly: [String: [Date: TokenUsage]] = [:]
        var seen: Set<String> = []
        var countedSessions: Set<String> = []
        var messageCount = 0

        for session in sessions {
            guard let stats = session.stats else { continue }
            let sessionActivity = stats.lastActivity ?? session.lastModified

            if !stats.billableMessages.isEmpty {
                var includedMessages = 0
                for bill in stats.billableMessages {
                    if let timestamp = bill.timestamp, !scope.contains(timestamp) { continue }
                    if bill.timestamp == nil, !scope.contains(sessionActivity) { continue }
                    if let hash = bill.hash {
                        if seen.contains(hash) { continue }
                        seen.insert(hash)
                    }
                    var acc = perModel[bill.model] ?? (0, .zero, .zero)
                    acc.count += 1
                    acc.usage += bill.usage
                    acc.cost += bill.cost
                    perModel[bill.model] = acc
                    includedMessages += 1
                    if let date = bill.timestamp, bill.usage.total > 0 {
                        let hour = calendar.dateInterval(of: .hour, for: date)?.start
                            ?? calendar.startOfDay(for: date)
                        perModelHourly[bill.model, default: [:]][hour, default: .zero] += bill.usage
                    }
                }
                if includedMessages > 0 {
                    countedSessions.insert(session.id)
                    messageCount += includedMessages
                }
                continue
            }

            if !stats.timeline.isEmpty {
                let buckets = stats.timeline.filter { scope.contains($0.start) }
                guard !buckets.isEmpty else { continue }
                countedSessions.insert(session.id)
                messageCount += stats.messageCount
                if scope.isUnbounded {
                    for model in stats.models {
                        var acc = perModel[model.model] ?? (0, .zero, .zero)
                        acc.count += model.messageCount
                        acc.usage += model.usage
                        acc.cost += model.costEstimate
                        perModel[model.model] = acc
                    }
                } else {
                    for bucket in buckets {
                        var acc = perModel[bucket.model] ?? (0, .zero, .zero)
                        acc.count += 1
                        acc.usage += bucket.usage
                        acc.cost += pricing.costEstimate(model: bucket.model, usage: bucket.usage)
                        perModel[bucket.model] = acc
                    }
                }
                for bucket in buckets {
                    perModelHourly[bucket.model, default: [:]][bucket.start, default: .zero] += bucket.usage
                }
                continue
            }

            if scope.contains(sessionActivity) {
                // Legacy provider-without-timeline path: trust the
                // already-aggregated per-session totals as-is.
                countedSessions.insert(session.id)
                messageCount += stats.messageCount
                for model in stats.models {
                    var acc = perModel[model.model] ?? (0, .zero, .zero)
                    acc.count += model.messageCount
                    acc.usage += model.usage
                    acc.cost += model.costEstimate
                    perModel[model.model] = acc
                }
                // If the session lost its hourly timeline (older transcript
                // parsers didn't persist one), synthesize a single bucket per
                // model anchored at the session's last activity so trend
                // charts and Usage rows still have something to render.
                let buckets: [ModelBucket]
                if !stats.timeline.isEmpty {
                    buckets = stats.timeline
                } else {
                    let activity = stats.lastActivity ?? session.lastModified
                    let bucketStart = calendar.dateInterval(of: .hour, for: activity)?.start ?? activity
                    buckets = stats.models.compactMap { model in
                        guard model.usage.total > 0 else { return nil }
                        return ModelBucket(model: model.model, start: bucketStart, usage: model.usage)
                    }
                }
                for bucket in buckets {
                    perModelHourly[bucket.model, default: [:]][bucket.start, default: .zero] += bucket.usage
                }
            }
        }

        let models = perModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, costEstimate: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }
        let timeline = perModelHourly
            .flatMap { model, byHour in byHour.map { ModelBucket(model: model, start: $0.key, usage: $0.value) } }
            .sorted { $0.start < $1.start }
        return AggregateResult(
            sessionCount: countedSessions.count,
            models: models,
            messageCount: messageCount,
            timeline: timeline
        )
    }

    private static func timelineBuckets(for sessions: [Session], calendar: Calendar) -> [ModelBucket] {
        sessions.flatMap { timelineBuckets(for: $0, calendar: calendar) }
    }

    private static func timelineBuckets(for session: Session, calendar: Calendar) -> [ModelBucket] {
        guard let stats = session.stats else { return [] }
        guard stats.timeline.isEmpty else { return stats.timeline }

        let activityDate = stats.lastActivity ?? session.lastModified
        let bucketStart = calendar.dateInterval(of: .hour, for: activityDate)?.start ?? activityDate
        return stats.models.compactMap { model in
            guard model.usage.total > 0 else { return nil }
            return ModelBucket(model: model.model, start: bucketStart, usage: model.usage)
        }
    }

    /// Per-model series for the trend chart: hourly across *today* for
    /// ``StatsPeriod/today``, daily across the span of ``timeline`` otherwise.
    /// Every `(model × bucket-in-span)` is present (zero-filled) so each model
    /// has a continuous series to smooth.
    func trendSeries(now: Date = .now, calendar: Calendar = .current) -> TrendSeries {
        let models = timeline.modelsByTotalDescending
        guard !models.isEmpty else { return TrendSeries(granularity: period == .today ? .hour : .day, models: [], buckets: []) }

        let granularity: TrendGranularity = period == .today ? .hour : .day
        let unit: Calendar.Component = granularity == .hour ? .hour : .day

        let bucketed = timeline.rebucketed(by: unit, calendar: calendar)
        var byKey: [String: TokenUsage] = [:]   // "model|epoch" -> usage
        for b in bucketed { byKey["\(b.model)|\(b.start.timeIntervalSinceReferenceDate)"] = b.usage }

        // Domain of bucket starts.
        let starts: [Date]
        switch granularity {
        case .hour:
            let dayStart = calendar.startOfDay(for: now)
            starts = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: dayStart) }
        case .day:
            guard let lo = bucketed.map(\.start).min(), let hi = bucketed.map(\.start).max() else {
                return TrendSeries(granularity: granularity, models: models, buckets: [])
            }
            var ds: [Date] = []
            var cur = lo
            while cur <= hi {
                ds.append(cur)
                guard let next = calendar.date(byAdding: unit, value: 1, to: cur) else { break }
                cur = next
            }
            starts = ds
        }

        var filled: [ModelBucket] = []
        filled.reserveCapacity(models.count * starts.count)
        for model in models {
            for start in starts {
                let usage = byKey["\(model)|\(start.timeIntervalSinceReferenceDate)"] ?? .zero
                filled.append(ModelBucket(model: model, start: start, usage: usage))
            }
        }
        return TrendSeries(granularity: granularity, models: models, buckets: filled)
    }
}

/// Time grain used by the Usage trend chart.
enum TrendGranularity: Sendable, Hashable { case hour, day }

/// The trend chart's data: a continuous, zero-filled per-model series.
struct TrendSeries: Sendable, Hashable {
    let granularity: TrendGranularity
    /// Models present, ordered by total tokens descending.
    let models: [String]
    /// Zero-filled buckets covering every `(model × bucket-in-span)`.
    let buckets: [ModelBucket]

    var isEmpty: Bool { buckets.allSatisfy { $0.tokens == 0 } }

    var dataRevisionID: String {
        var totalsByModel: [String: TokenUsage] = [:]
        var firstStart: Date?
        var lastStart: Date?
        for bucket in buckets {
            totalsByModel[bucket.model, default: .zero] += bucket.usage
            firstStart = min(firstStart ?? bucket.start, bucket.start)
            lastStart = max(lastStart ?? bucket.start, bucket.start)
        }

        let modelTotals = models.map { model in
            "\(model):\(totalsByModel[model, default: .zero].dataRevisionID)"
        }
        return [
            granularity.revisionID,
            models.joined(separator: ","),
            String(buckets.count),
            firstStart.map { String(Int($0.timeIntervalSinceReferenceDate.rounded())) } ?? "nil",
            lastStart.map { String(Int($0.timeIntervalSinceReferenceDate.rounded())) } ?? "nil",
            modelTotals.joined(separator: "|"),
        ]
        .joined(separator: "#")
    }

    func buckets(for model: String) -> [ModelBucket] {
        buckets.filter { $0.model == model }.sorted { $0.start < $1.start }
    }
}

private extension TrendGranularity {
    var revisionID: String {
        switch self {
        case .hour: "hour"
        case .day: "day"
        }
    }
}
