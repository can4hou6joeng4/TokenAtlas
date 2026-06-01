import SwiftUI

struct LocalInsightsView: View {
    @Environment(AppEnvironment.self) private var env

    @SceneStorage("mainWindow.insights.period") private var periodRaw: String = StatsPeriod.today.rawValue
    @SceneStorage("mainWindow.insights.chartStyle") private var chartStyleRaw: String = ChartStyleStorage.line.rawValue
    @SceneStorage("mainWindow.insights.scaleMode") private var scaleModeRaw: String = ScaleModeStorage.linear.rawValue
    @SceneStorage("mainWindow.insights.stackByType") private var stackByTypeRaw = false

    @State private var period: StatsPeriod = .today
    @State private var chartStyle: TrendChartStyle = .line
    @State private var scaleMode: TrendScaleMode = .linear
    @State private var stackByType = false

    private var provider: ProviderKind { env.preferences.selectedProvider }

    private var snapshot: LocalInsightsSnapshot {
        LocalInsightsSnapshot.make(
            provider: provider,
            sessions: env.store.sessions(for: provider),
            currentPeriod: period
        )
    }

    var body: some View {
        let snapshot = snapshot
        let summary = snapshot.currentPeriod
        let series = summary.trendSeries()
        let seriesID = [
            provider.rawValue,
            period.rawValue,
            env.store.lastRefreshedAt.map { String(Int($0.timeIntervalSinceReferenceDate.rounded())) } ?? "never",
        ].joined(separator: ":")

        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controls
                recordGrid(snapshot: snapshot)
                UsageTrendPanel(
                    series: series,
                    seriesID: seriesID,
                    rangeID: period.rawValue,
                    chartStyle: $chartStyle,
                    scaleMode: $scaleMode,
                    stackByType: $stackByType,
                    displayName: modelDisplayName
                )
                lowerPanels(snapshot: snapshot)
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { syncFromSceneStorage() }
        .onChange(of: period) { _, new in periodRaw = new.rawValue }
        .onChange(of: chartStyle) { _, new in chartStyleRaw = ChartStyleStorage(new).rawValue }
        .onChange(of: scaleMode) { _, new in scaleModeRaw = ScaleModeStorage(new).rawValue }
        .onChange(of: stackByType) { _, new in stackByTypeRaw = new }
        .onChange(of: provider) { _, _ in
            if StatsPeriod(rawValue: periodRaw) == nil {
                period = .today
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("local_insights.eyebrow", defaultValue: "LOCAL INSIGHTS"))
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text(L10n.string("local_insights.title", defaultValue: "Personal records"))
                .font(.sora(24, weight: .semibold))
            Text(L10n.format(
                "local_insights.subtitle",
                defaultValue: "Private usage records and trends for %@.",
                provider.displayName
            ))
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 12) {
            Spacer(minLength: 0)
            LocalInsightsPeriodChips(period: $period)
        }
    }

    private func recordGrid(snapshot: LocalInsightsSnapshot) -> some View {
        let summary = snapshot.currentPeriod
        return ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCard(label: L10n.string("usage.stat.tokens", defaultValue: "TOKENS"), value: Format.tokens(summary.totalTokens(includingCacheRead: env.preferences.includeCacheInTokens)))
                    StatCard(label: L10n.string("usage.stat.sessions", defaultValue: "SESSIONS"), value: "\(summary.sessionCount)")
                    StatCard(label: L10n.string("local_insights.stat.active_days", defaultValue: "ACTIVE DAYS"), value: "\(snapshot.activeDaysLast30)")
                    StatCard(label: L10n.string("local_insights.stat.best_day", defaultValue: "BEST DAY"), value: Format.tokens(snapshot.bestDayTokensLast30))
                }
                GridRow {
                    StatCard(label: L10n.string("usage.stat.messages", defaultValue: "MESSAGES"), value: Format.tokens(summary.messageCount))
                    StatCard(label: L10n.string("usage.stat.estimated_cost", defaultValue: "EST. COST"), value: Format.cost(summary.totalCost(for: env.preferences.costEstimationMode)))
                    StatCard(label: L10n.string("local_insights.stat.models", defaultValue: "MODELS"), value: "\(summary.models.count)")
                    StatCard(label: L10n.string("local_insights.stat.top_model", defaultValue: "TOP MODEL"), value: topModelLabel(summary), animatesNumericValue: false)
                }
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCard(label: L10n.string("usage.stat.tokens", defaultValue: "TOKENS"), value: Format.tokens(summary.totalTokens(includingCacheRead: env.preferences.includeCacheInTokens)))
                    StatCard(label: L10n.string("usage.stat.sessions", defaultValue: "SESSIONS"), value: "\(summary.sessionCount)")
                }
                GridRow {
                    StatCard(label: L10n.string("local_insights.stat.active_days", defaultValue: "ACTIVE DAYS"), value: "\(snapshot.activeDaysLast30)")
                    StatCard(label: L10n.string("local_insights.stat.best_day", defaultValue: "BEST DAY"), value: Format.tokens(snapshot.bestDayTokensLast30))
                }
                GridRow {
                    StatCard(label: L10n.string("usage.stat.messages", defaultValue: "MESSAGES"), value: Format.tokens(summary.messageCount))
                    StatCard(label: L10n.string("usage.stat.estimated_cost", defaultValue: "EST. COST"), value: Format.cost(summary.totalCost(for: env.preferences.costEstimationMode)))
                }
                GridRow {
                    StatCard(label: L10n.string("local_insights.stat.models", defaultValue: "MODELS"), value: "\(summary.models.count)")
                    StatCard(label: L10n.string("local_insights.stat.top_model", defaultValue: "TOP MODEL"), value: topModelLabel(summary), animatesNumericValue: false)
                }
            }
        }
    }

    private func lowerPanels(snapshot: LocalInsightsSnapshot) -> some View {
        MainWindowLowerPanelsLayout(
            widthPolicy: .leadingFixed(width: 440, trailingMinimumWidth: 420),
            spacing: 12
        ) {
            LocalInsightsRecordsPanel(
                records: snapshot.records,
                includeCacheInTokens: env.preferences.includeCacheInTokens,
                costMode: env.preferences.costEstimationMode,
                displayName: modelDisplayName
            )
            LocalInsightsProjectsPanel(projects: snapshot.topProjects)
        }
    }

    private func topModelLabel(_ summary: UsageSummary) -> String {
        guard let model = summary.models.first?.model else { return "--" }
        return modelDisplayName(model)
    }

    private func modelDisplayName(_ id: String) -> String {
        env.store.displayName(forModel: id, provider: provider)
    }

    private func syncFromSceneStorage() {
        period = StatsPeriod(rawValue: periodRaw) ?? .today
        chartStyle = ChartStyleStorage(rawValue: chartStyleRaw)?.chartStyle ?? .line
        scaleMode = ScaleModeStorage(rawValue: scaleModeRaw)?.scaleMode ?? .linear
        stackByType = stackByTypeRaw
    }
}

private struct LocalInsightsPeriodChips: View {
    @Binding var period: StatsPeriod

    private static let values: [StatsPeriod] = [.today, .last7Days, .last30Days, .allTime]

    var body: some View {
        PillSegmentedBar(
            Self.values,
            selection: $period,
            help: { $0.displayName }
        ) { value, _ in
            Text(label(for: value))
        }
    }

    private func label(for period: StatsPeriod) -> String {
        switch period {
        case .today: L10n.string("usage.period_chip.today", defaultValue: "Today")
        case .last7Days: "7d"
        case .last30Days: "30d"
        case .allTime: L10n.string("usage.period_chip.all", defaultValue: "All")
        }
    }
}

private struct LocalInsightsRecordsPanel: View {
    let records: [LocalInsightsSnapshot.PeriodRecord]
    let includeCacheInTokens: Bool
    let costMode: CostEstimationMode
    let displayName: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("local_insights.records.title", defaultValue: "PERSONAL RECORDS"))
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            VStack(spacing: 0) {
                ForEach(records) { record in
                    recordRow(record)
                    if record.id != records.last?.id {
                        Divider().opacity(0.45)
                    }
                }
            }
        }
        .fillingMainWindowPanel(padding: 16)
    }

    private func recordRow(_ record: LocalInsightsSnapshot.PeriodRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.period.displayName)
                    .font(.sora(12, weight: .semibold))
                Text(record.topModel.map(displayName) ?? L10n.string("local_insights.no_model_activity", defaultValue: "No model activity"))
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.tokens(record.tokens))
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                Text("\(L10n.sessionCount(record.sessions)) · \(Format.cost(record.cost))")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct LocalInsightsProjectsPanel: View {
    let projects: [LocalInsightsSnapshot.ProjectRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("local_insights.projects.title", defaultValue: "TOP PROJECTS"))
                .font(.sora(13, weight: .semibold))
                .tracking(1.0)
            if projects.isEmpty {
                Text(L10n.string("local_insights.projects.empty", defaultValue: "No local project records yet."))
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(projects) { project in
                        projectRow(project)
                        if project.id != projects.last?.id {
                            Divider().opacity(0.45)
                        }
                    }
                }
            }
        }
        .fillingMainWindowPanel(padding: 16)
    }

    private func projectRow(_ project: LocalInsightsSnapshot.ProjectRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.sora(12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L10n.sessionCount(project.sessions))
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 8)
            Text(Format.tokens(project.tokens))
                .font(.sora(12, weight: .semibold).monospacedDigit())
        }
        .padding(.vertical, 10)
    }
}

private enum ChartStyleStorage: String {
    case line, bar

    init(_ chartStyle: TrendChartStyle) {
        self = chartStyle == .line ? .line : .bar
    }

    var chartStyle: TrendChartStyle {
        switch self {
        case .line: .line
        case .bar: .bar
        }
    }
}

private enum ScaleModeStorage: String {
    case linear, log

    init(_ scaleMode: TrendScaleMode) {
        self = scaleMode == .linear ? .linear : .log
    }

    var scaleMode: TrendScaleMode {
        switch self {
        case .linear: .linear
        case .log: .log
        }
    }
}

#if DEBUG
#Preview("Local Insights") {
    LocalInsightsView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(Color.stxBackground)
}
#endif
