import Foundation
import Testing
@testable import TokenAtlas

@MainActor
@Suite("GitHub view model")
struct GitHubViewModelTests {
    @Test("Connect keeps saved token after transient fetch failure")
    func connectKeepsTokenAfterTransientFailure() async throws {
        let creds = MockGitHubCredentialsStore()
        let vm = GitHubViewModel(
            client: MockGitHubCalendarClient(result: .failure(GitHubClient.ClientError.network(URLError(.notConnectedToInternet)))),
            creds: creds
        )

        await #expect(throws: GitHubClient.ClientError.self) {
            try await vm.connect(token: " ghp_test ")
        }

        #expect(creds.savedToken == "ghp_test")
        #expect(creds.deleteCount == 0)
        #expect(vm.status == .disconnected)
    }

    @Test("Connect deletes token after unauthorized fetch failure")
    func connectDeletesTokenAfterUnauthorizedFailure() async throws {
        let creds = MockGitHubCredentialsStore()
        let vm = GitHubViewModel(
            client: MockGitHubCalendarClient(result: .failure(GitHubClient.ClientError.unauthorized)),
            creds: creds
        )

        await #expect(throws: GitHubClient.ClientError.self) {
            try await vm.connect(token: "ghp_bad")
        }

        #expect(creds.savedToken == nil)
        #expect(creds.deleteCount == 1)
        #expect(vm.status == .disconnected)
    }
}

private struct MockGitHubCalendarClient: GitHubCalendarFetching {
    let result: Result<GitHubClient.CalendarSnapshot, Error>

    func fetchCalendar(token: String, from: Date, to: Date, now: Date) async throws -> GitHubClient.CalendarSnapshot {
        try result.get()
    }
}

private final class MockGitHubCredentialsStore: GitHubCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private(set) var deleteCount = 0

    var savedToken: String? {
        lock.withLock { token }
    }

    func readToken() -> String? {
        lock.withLock { token }
    }

    func saveToken(_ token: String) throws {
        lock.withLock {
            self.token = token
        }
    }

    func deleteToken() {
        lock.withLock {
            deleteCount += 1
            token = nil
        }
    }
}
