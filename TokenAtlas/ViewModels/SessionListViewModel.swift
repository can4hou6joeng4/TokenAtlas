import Foundation
import Observation

/// UI state for the Sessions screen: a search query, a sort order, and which
/// project groups are expanded. The derived list is computed against a
/// ``SessionStore`` passed in by the view.
@MainActor
@Observable
final class SessionListViewModel {
    static let collapsedSessionLimit = 5

    var searchText: String = "" {
        didSet {
            if searchText != oldValue { rebuildProjectGroups() }
        }
    }
    var sortOrder: SortOrder = .recent {
        didSet {
            if sortOrder != oldValue { rebuildProjectGroups() }
        }
    }
    /// Project groups (keyed by ``Session/projectDirectoryName``) that are open.
    var expandedProjects: Set<String> = []
    /// Expanded project groups whose full session list is visible.
    var fullyVisibleProjects: Set<String> = []
    private(set) var projectGroups: [ProjectGroup] = []
    private(set) var hasProviderSessions = false

    @ObservationIgnored private var sourceSessions: [Session] = []
    @ObservationIgnored private var sourceProvider: ProviderKind?
    @ObservationIgnored private var sourceCostMode: CostEstimationMode = .standardAPI

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent, tokens, cost
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .recent: L10n.string("sessions.sort.recent", defaultValue: "Recent")
            case .tokens: L10n.string("sessions.sort.tokens", defaultValue: "Tokens")
            case .cost: L10n.string("sessions.sort.cost", defaultValue: "Cost")
            }
        }
    }

    /// One project's sessions, already filtered and sorted for display.
    struct ProjectGroup: Identifiable {
        let id: String          // projectDirectoryName
        let displayName: String
        let sessions: [Session]
        let lastActivity: Date
        var count: Int { sessions.count }
    }

    func toggle(_ groupID: String) {
        if expandedProjects.contains(groupID) {
            expandedProjects.remove(groupID)
            fullyVisibleProjects.remove(groupID)
        } else {
            expandedProjects.insert(groupID)
        }
    }

    func collapseAllProjects() {
        expandedProjects.removeAll()
        fullyVisibleProjects.removeAll()
    }

    func toggleFullSessionList(for groupID: String) {
        if fullyVisibleProjects.contains(groupID) {
            fullyVisibleProjects.remove(groupID)
        } else {
            fullyVisibleProjects.insert(groupID)
        }
    }

    func isFullSessionListVisible(for group: ProjectGroup) -> Bool {
        fullyVisibleProjects.contains(group.id)
    }

    func shouldShowSessionListToggle(for group: ProjectGroup) -> Bool {
        group.sessions.count > Self.collapsedSessionLimit
    }

    func visibleSessions(for group: ProjectGroup) -> [Session] {
        guard shouldShowSessionListToggle(for: group),
              !isFullSessionListVisible(for: group) else {
            return group.sessions
        }
        return Array(group.sessions.prefix(Self.collapsedSessionLimit))
    }

    func hiddenSessionCount(for group: ProjectGroup) -> Int {
        max(0, group.sessions.count - visibleSessions(for: group).count)
    }

    func refresh(from store: SessionStore, provider: ProviderKind, costMode: CostEstimationMode) {
        refresh(sessions: store.sessions(for: provider), provider: provider, costMode: costMode)
    }

    func refresh(sessions: [Session], provider: ProviderKind?, costMode: CostEstimationMode) {
        guard sourceProvider != provider || sourceSessions != sessions || sourceCostMode != costMode else { return }
        sourceProvider = provider
        sourceCostMode = costMode
        sourceSessions = sessions
        hasProviderSessions = !sessions.isEmpty
        rebuildProjectGroups()
    }

    private func rebuildProjectGroups() {
        projectGroups = makeProjectGroups(from: sourceSessions, costMode: sourceCostMode)
        let groupIDs = Set(projectGroups.map(\.id))
        expandedProjects.formIntersection(groupIDs)
        fullyVisibleProjects.formIntersection(groupIDs)
        fullyVisibleProjects.formIntersection(expandedProjects)
    }

    private func makeProjectGroups(from sourceSessions: [Session], costMode: CostEstimationMode) -> [ProjectGroup] {
        var sessions = sourceSessions

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            sessions = sessions.filter { session in
                session.projectDisplayName.lowercased().contains(query)
                    || (session.stats?.title.lowercased().contains(query) ?? false)
                    || (session.cwd?.lowercased().contains(query) ?? false)
            }
        }

        let grouped = Dictionary(grouping: sessions, by: \.projectDirectoryName)
        var groups = grouped.map { key, value -> ProjectGroup in
            let sorted = sortedSessions(value, costMode: costMode)
            let lastActivity = value
                .map { $0.stats?.lastActivity ?? $0.lastModified }
                .max() ?? .distantPast
            return ProjectGroup(
                id: key,
                displayName: sorted.first?.projectDisplayName ?? key,
                sessions: sorted,
                lastActivity: lastActivity
            )
        }
        groups.sort {
            if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        return groups
    }

    private func sortedSessions(_ sessions: [Session], costMode: CostEstimationMode) -> [Session] {
        switch sortOrder {
        case .recent:
            sessions.sorted { ($0.stats?.lastActivity ?? $0.lastModified) > ($1.stats?.lastActivity ?? $1.lastModified) }
        case .tokens:
            sessions.sorted { ($0.stats?.totalTokens ?? 0) > ($1.stats?.totalTokens ?? 0) }
        case .cost:
            sessions.sorted { ($0.stats?.totalCost(for: costMode) ?? 0) > ($1.stats?.totalCost(for: costMode) ?? 0) }
        }
    }
}
