import Foundation

struct LocalInsightsSnapshot: Sendable, Hashable {
    struct PeriodRecord: Sendable, Hashable, Identifiable {
        let period: StatsPeriod
        let tokens: Int
        let sessions: Int
        let messages: Int
        let cost: Double
        let topModel: String?

        var id: StatsPeriod { period }
    }

    struct ProjectRecord: Sendable, Hashable, Identifiable {
        let name: String
        let sessions: Int
        let tokens: Int
        let lastActivity: Date

        var id: String { name }
    }

    let provider: ProviderKind
    let generatedAt: Date
    let currentPeriod: UsageSummary
    let records: [PeriodRecord]
    let topProjects: [ProjectRecord]
    let activeDaysLast30: Int
    let bestDayTokensLast30: Int
    let bestDay: Date?

    var hasUsage: Bool {
        currentPeriod.sessionCount > 0 || records.contains { $0.sessions > 0 }
    }

    static func make(
        provider: ProviderKind,
        sessions: [Session],
        currentPeriod: StatsPeriod,
        pricing: ModelPricing = .fallback,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> LocalInsightsSnapshot {
        let providerSessions = sessions.filter { $0.provider == provider }
        let currentSummary = UsageSummary.make(
            period: currentPeriod,
            sessions: providerSessions,
            pricing: pricing,
            now: now,
            calendar: calendar
        )
        let records = [StatsPeriod.today, .last7Days, .last30Days, .allTime].map { period in
            let summary = UsageSummary.make(
                period: period,
                sessions: providerSessions,
                pricing: pricing,
                now: now,
                calendar: calendar
            )
            return PeriodRecord(
                period: period,
                tokens: summary.totalTokens,
                sessions: summary.sessionCount,
                messages: summary.messageCount,
                cost: summary.totalCost,
                topModel: summary.models.first?.model
            )
        }

        let last30Start = StatsPeriod.last30Days.lowerBound(now: now, calendar: calendar)
            ?? calendar.startOfDay(for: now)
        var tokensByDay: [Date: Int] = [:]
        var projectBuckets: [String: (sessions: Int, tokens: Int, lastActivity: Date)] = [:]

        for session in providerSessions {
            let activityDate = session.stats?.lastActivity ?? session.lastModified
            let projectName = session.projectDisplayName
            let tokens = session.stats?.totalTokens ?? 0
            var project = projectBuckets[projectName] ?? (0, 0, activityDate)
            project.sessions += 1
            project.tokens += tokens
            project.lastActivity = max(project.lastActivity, activityDate)
            projectBuckets[projectName] = project

            guard activityDate >= last30Start else { continue }
            let day = calendar.startOfDay(for: activityDate)
            tokensByDay[day, default: 0] += tokens
        }

        let topProjects = projectBuckets
            .map { name, value in
                ProjectRecord(
                    name: name,
                    sessions: value.sessions,
                    tokens: value.tokens,
                    lastActivity: value.lastActivity
                )
            }
            .sorted {
                if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
                if $0.sessions != $1.sessions { return $0.sessions > $1.sessions }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            .prefix(5)

        let bestDay = tokensByDay.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }

        return LocalInsightsSnapshot(
            provider: provider,
            generatedAt: now,
            currentPeriod: currentSummary,
            records: records,
            topProjects: Array(topProjects),
            activeDaysLast30: tokensByDay.filter { $0.value > 0 }.count,
            bestDayTokensLast30: bestDay?.value ?? 0,
            bestDay: bestDay?.key
        )
    }
}
