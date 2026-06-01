import SwiftUI

struct UsageModelBreakdown: View {
    let models: [ModelUsage]
    let series: TrendSeries
    let seriesID: String
    let includeCacheInTokens: Bool
    let costEstimationMode: CostEstimationMode
    let displayName: (String) -> String
    @State private var cachedSnapshotKey: UsageModelBreakdownSnapshot.Key?
    @State private var cachedSnapshot: UsageModelBreakdownSnapshot?

    var body: some View {
        let key = UsageModelBreakdownSnapshot.Key(
            seriesID: seriesID,
            includeCacheInTokens: includeCacheInTokens,
            costEstimationMode: costEstimationMode,
            modelsRevisionID: models.dataRevisionID,
            seriesRevisionID: series.dataRevisionID
        )
        let snapshot = cachedSnapshotKey == key
            ? (cachedSnapshot ?? makeSnapshot(key: key))
            : makeSnapshot(key: key)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("BY MODEL")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text("Tokens · Cost · Share")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            if snapshot.rows.isEmpty {
                Text("No model data in this range.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, minHeight: 98, alignment: .center)
            } else {
                UsageModelSummary(snapshot: snapshot)
                StxRule()
                LazyVStack(spacing: 0) {
                    ForEach(snapshot.rows) { row in
                        UsageModelRow(row: row)
                        if row.id != snapshot.rows.last?.id {
                            StxRule()
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .mainUsagePanel(padding: 16, fillHeight: true)
        .onAppear { cacheSnapshotIfNeeded(key) }
        .onChange(of: key) { _, newKey in cacheSnapshotIfNeeded(newKey) }
    }

    private func makeSnapshot(key: UsageModelBreakdownSnapshot.Key) -> UsageModelBreakdownSnapshot {
        UsageModelBreakdownSnapshot(
            key: key,
            models: models,
            series: series,
            displayName: displayName
        )
    }

    private func cacheSnapshotIfNeeded(_ key: UsageModelBreakdownSnapshot.Key) {
        guard cachedSnapshotKey != key else { return }
        cachedSnapshot = makeSnapshot(key: key)
        cachedSnapshotKey = key
    }
}

private struct UsageModelSummary: View {
    let snapshot: UsageModelBreakdownSnapshot

    private var primaryRow: UsageModelBreakdownSnapshot.Row? {
        snapshot.rows.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let primaryRow {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(primaryRow.displayName)
                            .font(.sora(18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(primaryRow.totalText) · \(primaryRow.costText)")
                            .font(.sora(11).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Text(primaryRow.shareText)
                        .font(.sora(20, weight: .semibold).monospacedDigit())
                        .stxNumericValueTransition(value: primaryRow.shareText)
                        .foregroundStyle(.primary)
                }
            }

            modelShareBar

            HStack(spacing: 16) {
                summaryMetric(
                    label: Text("Tokens"),
                    value: snapshot.solidText,
                    color: Color.primary.opacity(0.52)
                )
                summaryMetric(
                    label: Text(L10n.string("usage.token.cache_read", defaultValue: "Cache read")),
                    value: snapshot.cacheReadText,
                    color: Color.stxRamp[3],
                    striped: true
                )
            }
        }
        .padding(.bottom, 2)
    }

    private var modelShareBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(snapshot.rows) { row in
                    let width = proxy.size.width * CGFloat(row.totalTokens) / CGFloat(snapshot.totalTokens)
                    Rectangle()
                        .fill(ModelPalette.color(at: row.colorIndex))
                        .frame(width: max(row.totalTokens > 0 ? CGFloat(2) : 0, width))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: 9)
    }

    private func summaryMetric(
        label: Text,
        value: String,
        color: Color,
        striped: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                    if striped {
                        DiagonalStripes(spacing: 4)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    }
                }
                .frame(width: 9, height: 9)
                label
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }
            Text(value)
                .font(.sora(12, weight: .semibold).monospacedDigit())
                .stxNumericValueTransition(value: value)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageModelRow: View {
    let row: UsageModelBreakdownSnapshot.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ModelPalette.color(at: row.colorIndex))
                    .frame(width: 10, height: 10)
                Text(row.displayName)
                    .font(.sora(13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text(row.totalText)
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: row.totalText)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 72, alignment: .trailing)
                Text(row.costText)
                    .font(.sora(12).monospacedDigit())
                    .stxNumericValueTransition(value: row.costText)
                    .foregroundStyle(Color.stxMuted)
                    .frame(minWidth: 70, alignment: .trailing)
                Text(row.shareText)
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: row.shareText)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 50, alignment: .trailing)
            }

            GeometryReader { proxy in
                let totalWidth = proxy.size.width
                let solidWidth = totalWidth * CGFloat(row.solidTokens) / CGFloat(row.maxTokens)
                let cachedWidth = totalWidth * CGFloat(row.cacheReadTokens) / CGFloat(row.maxTokens)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    HStack(spacing: 0) {
                        if solidWidth > 0 {
                            Rectangle()
                                .fill(ModelPalette.color(at: row.colorIndex))
                                .frame(width: solidWidth)
                        }
                        if cachedWidth > 0 {
                            ZStack {
                                Rectangle().fill(ModelPalette.color(at: row.colorIndex).opacity(0.68))
                                DiagonalStripes(spacing: 4)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
                            }
                            .frame(width: cachedWidth)
                            .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
            }
            .frame(height: 7)
        }
        .padding(.vertical, 10)
    }
}

struct UsageModelBreakdownSnapshot {
    struct Key: Equatable {
        let seriesID: String
        let includeCacheInTokens: Bool
        let costEstimationMode: CostEstimationMode
        let modelsRevisionID: String
        let seriesRevisionID: String
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let displayName: String
        let colorIndex: Int
        let totalText: String
        let costText: String
        let shareText: String
        let totalTokens: Int
        let solidTokens: Int
        let cacheReadTokens: Int
        let maxTokens: Int
    }

    let key: Key
    let rows: [Row]
    let totalTokens: Int
    let solidTokens: Int
    let cacheReadTokens: Int

    var solidText: String { Format.tokens(solidTokens) }
    var cacheReadText: String { Format.tokens(cacheReadTokens) }

    init(
        key: Key,
        models: [ModelUsage],
        series: TrendSeries,
        displayName: (String) -> String
    ) {
        self.key = key

        let totals = models.map { $0.usage.total(includingCacheRead: key.includeCacheInTokens) }
        let allTokens = max(1, totals.reduce(0, +))
        let maxTokens = max(1, totals.max() ?? 1)
        let seriesIndexByModel = Dictionary(uniqueKeysWithValues: series.models.enumerated().map { ($0.element, $0.offset) })
        var displaySolidTokens = 0
        var displayCacheReadTokens = 0

        self.rows = models.enumerated().map { index, model in
            let total = totals[index]
            let share = Double(total) / Double(allTokens)
            let solidTokens = max(0, model.usage.total - model.usage.cacheReadTokens)
            let cacheReadTokens = key.includeCacheInTokens ? max(0, model.usage.cacheReadTokens) : 0
            displaySolidTokens += solidTokens
            displayCacheReadTokens += cacheReadTokens
            return Row(
                id: model.id,
                displayName: displayName(model.model),
                colorIndex: seriesIndexByModel[model.model] ?? index,
                totalText: Format.tokens(total),
                costText: Format.cost(model.estimatedCost(for: key.costEstimationMode)),
                shareText: Format.percent(share),
                totalTokens: total,
                solidTokens: solidTokens,
                cacheReadTokens: cacheReadTokens,
                maxTokens: maxTokens
            )
        }
        self.totalTokens = allTokens
        self.solidTokens = displaySolidTokens
        self.cacheReadTokens = displayCacheReadTokens
    }
}

struct UsageTokenCompositionPanel: View {
    let usage: TokenUsage
    let includeCacheInTokens: Bool
    let cacheHitRate: Double?

    private var parts: [Part] {
        [
            Part(id: "output", label: L10n.string("usage.token.output", defaultValue: "Output"), value: usage.outputTokens, color: Color.stxRamp[0]),
            Part(id: "input", label: L10n.string("usage.token.input", defaultValue: "Input"), value: usage.inputTokens, color: Color.stxRamp[1]),
            Part(id: "cache-write", label: L10n.string("usage.token.cache_write", defaultValue: "Cache write"), value: usage.cacheCreationTotalTokens, color: Color.stxRamp[2]),
            Part(id: "cache-read", label: L10n.string("usage.token.cache_read", defaultValue: "Cache read"), value: usage.cacheReadTokens, color: Color.stxRamp[3]),
        ]
    }

    private var compositionTotal: Int {
        max(1, parts.reduce(0) { $0 + $1.value })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("COMPOSITION")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Text(cacheHitRate.map(Format.percent) ?? "--")
                    .font(.sora(12, weight: .semibold).monospacedDigit())
                    .stxNumericValueTransition(value: cacheHitRate.map(Format.percent) ?? "--")
                    .foregroundStyle(.primary)
                    .help(L10n.string("usage.token.cache_hit_rate", defaultValue: "Cache hit rate"))
            }

            compositionBar

            VStack(alignment: .leading, spacing: 8) {
                ForEach(parts) { part in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(part.color)
                            .frame(width: 9, height: 9)
                        Text(part.label)
                            .font(.sora(11))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.tokens(part.value))
                            .font(.sora(11).monospacedDigit())
                            .stxNumericValueTransition(value: Format.tokens(part.value))
                            .foregroundStyle(Color.stxMuted)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
            }

            StxRule()

            VStack(alignment: .leading, spacing: 5) {
                Text(includeCacheInTokens
                    ? L10n.string("usage.token.cache_reads_included", defaultValue: "Cache reads are included in totals.")
                    : L10n.string("usage.token.cache_reads_excluded", defaultValue: "Cache reads are excluded from totals."))
                    .font(.sora(11, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.string("usage.token.cache_write_note",
                                 defaultValue: "Cache write tokens are always counted because they represent newly primed context."))
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .mainUsagePanel(padding: 16, fillHeight: true)
    }

    private var compositionBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(parts) { part in
                    let width = proxy.size.width * CGFloat(part.value) / CGFloat(compositionTotal)
                    Rectangle()
                        .fill(part.color)
                        .frame(width: max(part.value > 0 ? CGFloat(2) : 0, width))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: 8)
    }

    private struct Part: Identifiable {
        let id: String
        let label: String
        let value: Int
        let color: Color
    }
}

#if DEBUG
#Preview {
    UsageTokenCompositionPanel(
        usage: TokenUsage(inputTokens: 120_000, outputTokens: 82_000, cacheReadTokens: 800_000, cacheCreation5mTokens: 12_000, cacheCreation1hTokens: 44_000),
        includeCacheInTokens: true,
        cacheHitRate: 0.88
    )
    .padding(24)
    .frame(width: 360)
    .background(Color.stxBackground)
}
#endif
