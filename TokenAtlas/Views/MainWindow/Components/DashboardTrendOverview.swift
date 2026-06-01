import SwiftUI

/// Compact all-provider token trend for the Dashboard overview. It consumes
/// the DashboardViewModel's already-rebucketed model trend, then aggregates it
/// to one visible total per bucket so the overview stays useful even when
/// optional heatmaps are disabled.
struct DashboardTrendOverview: View {
    let series: TrendSeries
    let seriesID: String

    @State private var cachedSnapshotKey: DashboardTrendOverviewSnapshot.Key?
    @State private var cachedSnapshot: DashboardTrendOverviewSnapshot?

    private static let chartHeight: CGFloat = 88
    private static let yAxisWidth: CGFloat = 44

    private var snapshotKey: DashboardTrendOverviewSnapshot.Key {
        DashboardTrendOverviewSnapshot.Key(seriesID: seriesID, seriesRevisionID: series.dataRevisionID)
    }

    var body: some View {
        let key = snapshotKey
        let snapshot = cachedSnapshotKey == key
            ? (cachedSnapshot ?? makeSnapshot(key: key))
            : makeSnapshot(key: key)

        VStack(alignment: .leading, spacing: 12) {
            header(snapshot)
            metrics(snapshot)
            chart(snapshot)
        }
        .mainWindowPanel(padding: 16)
        .onAppear { cacheSnapshotIfNeeded(key) }
        .onChange(of: key) { _, newKey in cacheSnapshotIfNeeded(newKey) }
    }

    private func header(_ snapshot: DashboardTrendOverviewSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L10n.string("dashboard.trend.title", defaultValue: "令牌趋势"))
                .font(.sora(13, weight: .semibold))
            Spacer()
            Text(snapshot.caption)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    private func metrics(_ snapshot: DashboardTrendOverviewSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            metric(
                L10n.string("dashboard.trend.metric.total", defaultValue: "总令牌"),
                Format.tokens(snapshot.totalTokens)
            )
            metric(
                L10n.string("dashboard.trend.metric.active_days", defaultValue: "活跃天"),
                "\(snapshot.activeBucketCount)"
            )
            metric(
                L10n.string("dashboard.trend.metric.average", defaultValue: "日均令牌"),
                Format.tokens(snapshot.averageTokensPerActiveBucket)
            )
            metric(
                L10n.string("dashboard.trend.metric.peak", defaultValue: "高峰日"),
                snapshot.peakBucket.map { Format.day($0.date) } ?? "-"
            )
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.sora(9, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chart(_ snapshot: DashboardTrendOverviewSnapshot) -> some View {
        if snapshot.isEmpty {
            Text(L10n.string("dashboard.trend.empty", defaultValue: "当前周期暂无令牌趋势。"))
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .frame(maxWidth: .infinity, minHeight: Self.chartHeight, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    yAxis(snapshot)
                    plotArea(snapshot)
                }
                .frame(height: Self.chartHeight)
                xAxis(snapshot)
            }
        }
    }

    private func yAxis(_ snapshot: DashboardTrendOverviewSnapshot) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(snapshot.yTicks.enumerated()), id: \.offset) { index, value in
                Text(Format.tokens(value))
                    .font(.sora(8).monospacedDigit())
                    .foregroundStyle(Color.stxMuted.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if index < snapshot.yTicks.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: Self.yAxisWidth)
    }

    private func plotArea(_ snapshot: DashboardTrendOverviewSnapshot) -> some View {
        Canvas { context, size in
            let rect = CGRect(x: 0, y: 4, width: size.width, height: max(1, size.height - 8))
            drawGrid(context: &context, rect: rect)
            guard snapshot.buckets.count > 1 else {
                drawSinglePoint(context: &context, snapshot: snapshot, rect: rect)
                return
            }
            let points = trendPoints(snapshot: snapshot, rect: rect)
            drawArea(context: &context, points: points, rect: rect)
            drawLine(context: &context, points: points)
        }
    }

    private func drawGrid(context: inout GraphicsContext, rect: CGRect) {
        for i in 0...DashboardTrendOverviewSnapshot.yTickCount {
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(DashboardTrendOverviewSnapshot.yTickCount)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(path, with: .color(Color.stxStroke.opacity(0.42)), lineWidth: 0.5)
        }
    }

    private func drawSinglePoint(context: inout GraphicsContext, snapshot: DashboardTrendOverviewSnapshot, rect: CGRect) {
        guard let bucket = snapshot.buckets.first, bucket.tokens > 0 else { return }
        let normalized = CGFloat(bucket.tokens) / CGFloat(max(snapshot.yMax, 1))
        let point = CGPoint(x: rect.midX, y: rect.maxY - rect.height * min(max(normalized, 0), 1))
        var line = Path()
        line.move(to: CGPoint(x: rect.minX, y: point.y))
        line.addLine(to: CGPoint(x: rect.maxX, y: point.y))
        context.stroke(line, with: .color(Color.stxAccent.opacity(0.84)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)), with: .color(Color.stxAccent.opacity(0.86)))
    }

    private func trendPoints(snapshot: DashboardTrendOverviewSnapshot, rect: CGRect) -> [CGPoint] {
        let count = snapshot.buckets.count
        guard count > 1 else { return [] }
        return snapshot.buckets.enumerated().map { index, bucket in
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(count - 1)
            let normalized = CGFloat(bucket.tokens) / CGFloat(max(snapshot.yMax, 1))
            let y = rect.maxY - rect.height * min(max(normalized, 0), 1)
            return CGPoint(x: x, y: y)
        }
    }

    private func drawArea(context: inout GraphicsContext, points: [CGPoint], rect: CGRect) {
        guard let first = points.first, let last = points.last else { return }
        var area = Path()
        area.move(to: CGPoint(x: first.x, y: rect.maxY))
        area.addLine(to: first)
        for point in points.dropFirst() {
            area.addLine(to: point)
        }
        area.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        area.closeSubpath()
        context.fill(area, with: .color(Color.stxAccent.opacity(0.13)))
    }

    private func drawLine(context: inout GraphicsContext, points: [CGPoint]) {
        guard let first = points.first else { return }
        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() {
            line.addLine(to: point)
        }
        context.stroke(line, with: .color(Color.stxAccent.opacity(0.88)), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
    }

    private func xAxis(_ snapshot: DashboardTrendOverviewSnapshot) -> some View {
        HStack(alignment: .top, spacing: 1) {
            Color.clear.frame(width: Self.yAxisWidth + 8)
            HStack(alignment: .top, spacing: 1) {
                ForEach(Array(snapshot.buckets.enumerated()), id: \.element.id) { index, bucket in
                    Text(snapshot.xLabelIndices.contains(index) ? snapshot.xLabel(for: bucket.date) : "")
                        .font(.sora(8).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private func makeSnapshot(key: DashboardTrendOverviewSnapshot.Key) -> DashboardTrendOverviewSnapshot {
        DashboardTrendOverviewSnapshot(key: key, series: series)
    }

    private func cacheSnapshotIfNeeded(_ key: DashboardTrendOverviewSnapshot.Key) {
        guard cachedSnapshotKey != key else { return }
        cachedSnapshot = makeSnapshot(key: key)
        cachedSnapshotKey = key
    }
}

struct DashboardTrendOverviewSnapshot: Equatable {
    struct Key: Equatable {
        let seriesID: String
        let seriesRevisionID: String
    }

    struct Bucket: Identifiable, Equatable {
        let date: Date
        let tokens: Int

        var id: Date { date }
    }

    let key: Key
    let granularity: TrendGranularity
    let buckets: [Bucket]
    let totalTokens: Int
    let activeBucketCount: Int
    let averageTokensPerActiveBucket: Int
    let peakBucket: Bucket?
    let yMax: Int
    let yTicks: [Int]
    let xLabelIndices: Set<Int>

    static let yTickCount = 4
    private static let targetXLabelCount = 8

    init(key: Key, series: TrendSeries) {
        var totalsByStart: [Date: Int] = [:]
        for bucket in series.buckets {
            totalsByStart[bucket.start, default: 0] += bucket.tokens
        }

        let buckets = totalsByStart
            .map { Bucket(date: $0.key, tokens: $0.value) }
            .sorted { $0.date < $1.date }
        let totalTokens = buckets.reduce(0) { $0 + $1.tokens }
        let activeBucketCount = buckets.reduce(0) { $0 + ($1.tokens > 0 ? 1 : 0) }

        self.key = key
        self.granularity = series.granularity
        self.buckets = buckets
        self.totalTokens = totalTokens
        self.activeBucketCount = activeBucketCount
        self.averageTokensPerActiveBucket = activeBucketCount > 0 ? totalTokens / activeBucketCount : 0
        self.peakBucket = buckets.max { lhs, rhs in
            lhs.tokens == rhs.tokens ? lhs.date > rhs.date : lhs.tokens < rhs.tokens
        }
        let yMax = Self.niceCeiling(buckets.map(\.tokens).max() ?? 0)
        self.yMax = yMax
        self.yTicks = Self.makeYTicks(yMax: yMax)
        self.xLabelIndices = Self.makeXLabelIndices(bucketCount: buckets.count)
    }

    var isEmpty: Bool {
        buckets.isEmpty || totalTokens == 0
    }

    var caption: String {
        switch granularity {
        case .hour:
            L10n.string("dashboard.trend.caption.hourly", defaultValue: "当前周期 · 按小时汇总")
        case .day:
            L10n.string("dashboard.trend.caption.daily", defaultValue: "当前周期 · 按日汇总")
        }
    }

    func xLabel(for date: Date) -> String {
        switch granularity {
        case .hour:
            date.formatted(.dateTime.hour())
        case .day:
            Format.day(date)
        }
    }

    static func niceCeiling(_ value: Int) -> Int {
        guard value > 0 else { return 1 }
        let magnitude = pow(10.0, floor(log10(Double(value))))
        let normalized = Double(value) / magnitude
        let nice: Double
        switch normalized {
        case ...1: nice = 1
        case ...2: nice = 2
        case ...2.5: nice = 2.5
        case ...5: nice = 5
        default: nice = 10
        }
        return Int((nice * magnitude).rounded(.up))
    }

    private static func makeYTicks(yMax: Int) -> [Int] {
        let step = max(1, yMax / yTickCount)
        return (0...yTickCount).map { max(0, yMax - $0 * step) }
    }

    private static func makeXLabelIndices(bucketCount: Int) -> Set<Int> {
        guard bucketCount > 0 else { return [] }
        if bucketCount <= targetXLabelCount { return Set(0..<bucketCount) }
        let step = Double(bucketCount - 1) / Double(targetXLabelCount - 1)
        return Set((0..<targetXLabelCount).map { Int((Double($0) * step).rounded()) })
    }
}

#if DEBUG
#Preview {
    DashboardTrendOverview(
        series: UsageSummary.empty(period: .last30Days).trendSeries(),
        seriesID: "preview"
    )
    .padding(24)
    .frame(width: 760)
    .background(Color.stxBackground)
}
#endif
