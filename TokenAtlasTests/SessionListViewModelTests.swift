import Foundation
import Testing
@testable import TokenAtlas

@MainActor
struct SessionListViewModelTests {
    @Test("Expanded projects default to five visible sessions")
    func expandedProjectsDefaultToCollapsedSessionLimit() throws {
        let vm = SessionListViewModel()
        vm.refresh(
            sessions: makeSessions(project: "alpha", count: 7),
            provider: .codex,
            costMode: .standardAPI
        )

        let group = try #require(vm.projectGroups.first)

        #expect(vm.visibleSessions(for: group).map(\.id) == [
            "alpha-0",
            "alpha-1",
            "alpha-2",
            "alpha-3",
            "alpha-4",
        ])
        #expect(vm.hiddenSessionCount(for: group) == 2)
        #expect(vm.shouldShowSessionListToggle(for: group))
    }

    @Test("Project session list can expand and collapse independently")
    func togglesFullProjectSessionList() throws {
        let vm = SessionListViewModel()
        vm.refresh(
            sessions: makeSessions(project: "alpha", count: 7),
            provider: .codex,
            costMode: .standardAPI
        )

        let group = try #require(vm.projectGroups.first)
        vm.toggleFullSessionList(for: group.id)

        #expect(vm.isFullSessionListVisible(for: group))
        #expect(vm.visibleSessions(for: group).count == 7)
        #expect(vm.hiddenSessionCount(for: group) == 0)

        vm.toggleFullSessionList(for: group.id)

        #expect(!vm.isFullSessionListVisible(for: group))
        #expect(vm.visibleSessions(for: group).count == SessionListViewModel.collapsedSessionLimit)
    }

    @Test("Collapsing a project clears its full-list state")
    func collapsingProjectClearsFullSessionListState() throws {
        let vm = SessionListViewModel()
        vm.refresh(
            sessions: makeSessions(project: "alpha", count: 7),
            provider: .codex,
            costMode: .standardAPI
        )

        let group = try #require(vm.projectGroups.first)
        vm.toggle(group.id)
        vm.toggleFullSessionList(for: group.id)

        #expect(vm.expandedProjects.contains(group.id))
        #expect(vm.fullyVisibleProjects.contains(group.id))

        vm.toggle(group.id)

        #expect(!vm.expandedProjects.contains(group.id))
        #expect(!vm.fullyVisibleProjects.contains(group.id))
    }

    @Test("Refresh prunes stale expansion state")
    func refreshPrunesStaleExpansionState() throws {
        let vm = SessionListViewModel()
        vm.refresh(
            sessions: makeSessions(project: "alpha", count: 7) + makeSessions(project: "beta", count: 2),
            provider: .codex,
            costMode: .standardAPI
        )

        let alpha = try #require(vm.projectGroups.first { $0.displayName == "alpha" })
        vm.toggle(alpha.id)
        vm.toggleFullSessionList(for: alpha.id)

        vm.searchText = "beta"

        #expect(vm.projectGroups.map(\.displayName) == ["beta"])
        #expect(vm.expandedProjects.isEmpty)
        #expect(vm.fullyVisibleProjects.isEmpty)
    }

    private func makeSessions(project: String, count: Int) -> [Session] {
        let baseDate = ISO8601DateFormatter().date(from: "2026-05-28T00:00:00Z")!
        return (0..<count).map { index in
            let lastActivity = baseDate.addingTimeInterval(TimeInterval(-index * 60))
            let usage = TokenUsage(inputTokens: 10, outputTokens: 5)
            return Session(
                id: "\(project)-\(index)",
                externalID: "\(project)-external-\(index)",
                provider: .codex,
                projectDirectoryName: project,
                filePath: "/tmp/\(project)-\(index).jsonl",
                cwd: "/tmp/\(project)",
                lastModified: lastActivity,
                fileSize: 128,
                stats: SessionStats(
                    title: "\(project) \(index)",
                    messageCount: 1,
                    firstActivity: lastActivity,
                    lastActivity: lastActivity,
                    models: [
                        ModelUsage(
                            model: "gpt-5",
                            messageCount: 1,
                            usage: usage,
                            costEstimate: .zero
                        ),
                    ],
                    timeline: [
                        ModelBucket(model: "gpt-5", start: lastActivity, usage: usage),
                    ]
                )
            )
        }
    }
}
