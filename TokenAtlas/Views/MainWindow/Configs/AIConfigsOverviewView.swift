import SwiftUI

struct AIConfigsOverviewView: View {
    let searchText: String

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryGrid
                planSummary
                coverageSummary
                diagnosticsSummary
                projectSummary
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
    }

    private var summaryGrid: some View {
        let summary = env.aiConfigs.snapshot.summary
        return LazyVGrid(columns: metricColumns, spacing: 12) {
            AIConfigsMetricCard(title: L10n.string("ai_configs.metric.files", defaultValue: "Files"), value: "\(summary.existingDocumentCount)", symbol: "doc.text")
            AIConfigsMetricCard(title: L10n.string("ai_configs.metric.projects", defaultValue: "Projects"), value: "\(summary.projectCount)", symbol: "folder")
            AIConfigsMetricCard(title: L10n.string("ai_configs.metric.plans", defaultValue: "Plans"), value: "\(summary.planStats.total)", symbol: "checklist")
            AIConfigsMetricCard(
                title: L10n.string("ai_configs.metric.diagnostics", defaultValue: "Diagnostics"),
                value: "\(summary.diagnosticCount)",
                symbol: "exclamationmark.triangle",
                tint: summary.diagnosticCount > 0 ? Color(red: 0.92, green: 0.58, blue: 0.16) : Color.stxAccent
            )
        }
    }

    private var planSummary: some View {
        let stats = env.aiConfigs.snapshot.summary.planStats
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.string("ai_configs.overview.plan_ownership", defaultValue: "Plan Ownership"), symbol: "checklist")
            LazyVGrid(columns: metricColumns, spacing: 12) {
                AIConfigsMetricCard(title: L10n.string("ai_configs.metric.assigned", defaultValue: "Assigned"), value: "\(stats.assigned)", symbol: "folder.badge.gearshape")
                AIConfigsMetricCard(title: L10n.string("ai_configs.metric.unassigned", defaultValue: "Unassigned"), value: "\(stats.unassigned)", symbol: "tray")
                AIConfigsMetricCard(title: L10n.string("ai_configs.metric.open_tasks", defaultValue: "Open Tasks"), value: "\(stats.uncheckedTasks)", symbol: "square")
                AIConfigsMetricCard(title: L10n.string("ai_configs.metric.done_tasks", defaultValue: "Done Tasks"), value: "\(stats.checkedTasks)", symbol: "checkmark.square")
            }
        }
        .mainWindowPanel()
    }

    private var coverageSummary: some View {
        let summary = env.aiConfigs.snapshot.summary
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.string("ai_configs.overview.coverage", defaultValue: "Coverage"), symbol: "scope")
            HStack(spacing: 12) {
                coverageRow(title: L10n.string("ai_configs.metric.existing", defaultValue: "Existing"), count: summary.existingDocumentCount, tint: Color.stxAccent)
                coverageRow(title: L10n.string("ai_configs.metric.missing_expected", defaultValue: "Missing Expected"), count: summary.missingExpectedCount, tint: Color.stxMuted)
                coverageRow(title: L10n.string("ai_configs.metric.total_sources", defaultValue: "Total Sources"), count: summary.documentCount, tint: Color.stxMuted)
            }
        }
        .mainWindowPanel()
    }

    private var diagnosticsSummary: some View {
        let diagnosticsProjects = env.aiConfigs.filteredProjects(section: .diagnostics, query: searchText)
        let documents = diagnosticsProjects.flatMap(\.documents)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.string("ai_configs.overview.diagnostics", defaultValue: "Diagnostics"), symbol: "exclamationmark.triangle")
            if documents.isEmpty {
                Text(searchText.isEmpty
                     ? L10n.string("ai_configs.empty.no_diagnostics", defaultValue: "No config diagnostics.")
                     : L10n.string("ai_configs.empty.no_matching_diagnostics", defaultValue: "No diagnostics match the current search."))
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(documents.prefix(5)) { document in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: document.diagnostics.contains(where: { $0.severity == .error }) ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                                .foregroundStyle(document.diagnostics.contains(where: { $0.severity == .error }) ? Color(red: 0.85, green: 0.22, blue: 0.18) : Color(red: 0.92, green: 0.58, blue: 0.16))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.title)
                                    .font(.sora(11, weight: .semibold))
                                    .lineLimit(1)
                                Text(document.diagnostics.first?.message ?? L10n.string("ai_configs.diagnostic.available", defaultValue: "Diagnostic available"))
                                    .font(.sora(10))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            AIConfigsBadge(text: "\(document.diagnostics.count)", color: Color.stxMuted)
                        }
                    }
                }
            }
        }
        .mainWindowPanel()
    }

    private var projectSummary: some View {
        let projects = env.aiConfigs
            .filteredProjects(section: .overview, query: searchText)
            .sorted {
                if $0.summary.existingDocumentCount != $1.summary.existingDocumentCount {
                    return $0.summary.existingDocumentCount > $1.summary.existingDocumentCount
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.string("ai_configs.overview.scopes", defaultValue: "Scopes"), symbol: "folder")
            if projects.isEmpty {
                Text(searchText.isEmpty
                     ? L10n.string("ai_configs.empty.no_scopes", defaultValue: "No config scopes discovered yet.")
                     : L10n.string("ai_configs.empty.no_matching_scopes", defaultValue: "No scopes match the current search."))
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(projects.prefix(8)) { project in
                        HStack(spacing: 10) {
                            Image(systemName: project.configsIconName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.stxMuted)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.sora(11, weight: .semibold))
                                    .lineLimit(1)
                                Text(project.configsDetailText)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            AIConfigsMiniStat(value: "\(project.summary.existingDocumentCount)", label: L10n.string("ai_configs.label.files", defaultValue: "files"))
                            AIConfigsMiniStat(value: "\(project.summary.diagnosticCount)", label: L10n.string("ai_configs.label.issues", defaultValue: "issues"))
                        }
                    }
                }
            }
        }
        .mainWindowPanel()
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
            Text(title)
                .font(.sora(14, weight: .semibold))
            Spacer(minLength: 0)
        }
    }

    private func coverageRow(title: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.stxMuted)
            Text("\(count)")
                .font(.sora(18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}
