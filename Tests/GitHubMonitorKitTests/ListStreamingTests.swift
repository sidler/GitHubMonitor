import Foundation
import Testing

@testable import GitHubMonitorKit

/// What the rounds reported, in order, from whichever thread they arrived
/// on.
private final class Rounds: @unchecked Sendable {
    private var counts: [Int] = []
    private let lock = NSLock()

    func saw(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        counts.append(count)
    }

    var all: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }
}

@Suite("A list that arrives in rounds")
struct ListStreamingTests {
    private let reviews = ListSearch(
        listID: "reviews", content: .pullRequests, query: "is:pr review-requested:@me"
    )

    private func node(id: String) -> [String: Any] {
        [
            "id": id, "number": 1, "title": "t", "url": "https://github.com/a/b/pull/1",
            "updatedAt": "2026-09-20T10:00:00Z",
            "repository": ["nameWithOwner": "octo/platform"],
            "author": ["login": "mira"],
        ]
    }

    /// One answer to one round, in the envelope GitHub puts it in.
    private func page(_ ids: [String], total: Int, next: String? = nil) throws -> StubGitHub.Answer {
        let payload: [String: Any] = [
            "data": [
                "rateLimit": [
                    "limit": 5000, "remaining": 4990,
                    "resetAt": "2026-09-20T11:00:00Z", "cost": 1,
                ],
                "s0": [
                    "issueCount": total,
                    "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any],
                    "nodes": ids.map { node(id: $0) },
                ],
            ]
        ]
        return StubGitHub.Answer(body: try JSONSerialization.data(withJSONObject: payload))
    }

    private func service(_ stub: StubGitHub.Stub) -> GitHubService {
        GitHubService(token: "token", session: stub.session)
    }

    @Test("Each round says what has arrived so far, and never less than the one before")
    func reportsEveryRound() async throws {
        let stub = StubGitHub.answering([
            try page(["1", "2"], total: 3, next: "cursor-1"),
            try page(["3"], total: 3),
        ])
        let rounds = Rounds()

        let fetched = try await service(stub).lists([reviews]) { partial in
            rounds.saw(partial.pullRequests["reviews"]?.count ?? 0)
        }

        // The window is filled from the first of these rather than from
        // the last: two rows on screen while the second page is still in
        // the air is the whole point.
        #expect(rounds.all == [2, 3])
        #expect(fetched.results.pullRequests["reviews"]?.count == 3)
    }

    @Test("A single round still reports itself")
    func reportsOneRound() async throws {
        let stub = StubGitHub.answering([try page(["1"], total: 1)])
        let rounds = Rounds()

        _ = try await service(stub).lists([reviews]) { partial in
            rounds.saw(partial.pullRequests["reviews"]?.count ?? 0)
        }

        #expect(rounds.all == [1])
    }

    @Test("Nobody has to be listening")
    func worksWithoutAListener() async throws {
        let stub = StubGitHub.answering([try page(["1", "2"], total: 2)])

        let fetched = try await service(stub).lists([reviews])

        #expect(fetched.results.pullRequests["reviews"]?.count == 2)
    }

    @Test("A round that fails is not reported as a round")
    func saysNothingAboutAFailedRound() async {
        // The second page never arrives; what the first one said has
        // already been shown, and the error is what the caller gets.
        //
        // Refused rather than timed out, so the test does not sit through
        // the waits -- what is being asked here is what a round that
        // failed reports, not how long the client waits before giving up.
        let stub = StubGitHub.answering([
            (try? page(["1", "2"], total: 3, next: "cursor-1")) ?? StubGitHub.Answer(),
            StubGitHub.Answer(status: 422),
        ])
        let rounds = Rounds()
        let service = service(stub)

        await #expect(throws: GitHubError.self) {
            _ = try await service.lists([self.reviews]) { partial in
                rounds.saw(partial.pullRequests["reviews"]?.count ?? 0)
            }
        }
        #expect(rounds.all == [2])
    }
}
