import Foundation
import Testing

@testable import GitHubMonitorKit

/// A stand-in for GitHub, so what the client does with a gateway error can
/// be watched rather than reasoned about.
///
/// It answers from a script of statuses, one per attempt, and keeps every
/// request it was given. The request it keeps has no body: URLSession hands
/// a protocol the body as a stream, which is why nothing here asks what was
/// posted -- only how many times.
final class StubGitHub: URLProtocol, @unchecked Sendable {
    private struct Script {
        var answers: [Int] = []
        var sent: [URLRequest] = []
    }

    nonisolated(unsafe) private static var script = Script()
    private static let lock = NSLock()

    /// The statuses to answer with, in order. Anything asked past the end
    /// of the script gets a 200, so a script is a statement about the
    /// beginning of a conversation rather than all of it.
    static func answering(_ statuses: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        script = Script(answers: statuses)
    }

    static var sent: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return script.sent
    }

    private static func next(for request: URLRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        script.sent.append(request)
        return script.answers.isEmpty ? 200 : script.answers.removeFirst()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubGitHub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let status = Self.next(for: request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":{}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Collects what the client reports about each request, from whichever
/// thread it finished on.
private final class Log: @unchecked Sendable {
    private var records: [RequestRecord] = []
    private let lock = NSLock()

    func add(_ record: RequestRecord) {
        lock.lock()
        defer { lock.unlock() }
        records.append(record)
    }

    var all: [RequestRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}

/// Serialised: these share one stub, and a script read by two tests at once
/// is a script neither of them wrote.
@Suite("A gateway that did not answer", .serialized)
struct RetryTests {
    private let rest = URL(string: "https://api.github.com/notifications")!
    private let graphQL = URL(string: "https://api.github.com/graphql")!

    /// No waiting: how long the client waits is tested by reading the
    /// constant, not by sitting through it.
    private func client(
        _ session: URLSession, watch: (@Sendable (RequestRecord) -> Void)? = nil
    ) -> GitHubClient {
        GitHubClient(token: "token", session: session, watch: watch, retryDelays: [.zero, .zero])
    }

    @Test("A 502 on a read is asked again, and the answer that follows is the one used")
    func sendsAReadAgain() async throws {
        StubGitHub.answering([502, 502, 200])
        let (_, response) = try await client(StubGitHub.session()).get(rest)

        #expect(response.statusCode == 200)
        #expect(StubGitHub.sent.count == 3)
    }

    @Test("It gives up rather than keep asking")
    func stopsAsking() async {
        StubGitHub.answering([502, 502, 502, 200])
        let client = client(StubGitHub.session())

        await #expect(throws: GitHubError.self) {
            _ = try await client.get(self.rest)
        }
        // The first send and the two the delays allow, and no fourth --
        // a timed-out request draws points from the hour's allowance, so
        // asking forever costs twice over.
        #expect(StubGitHub.sent.count == 3)
    }

    @Test("All three gateway statuses count", arguments: [502, 503, 504])
    func everyGatewayStatus(status: Int) async throws {
        StubGitHub.answering([status, 200])
        _ = try await client(StubGitHub.session()).get(rest)

        #expect(StubGitHub.sent.count == 2)
    }

    @Test("A refusal that will say the same next time is asked once", arguments: [401, 404, 422])
    func doesNotRepeatARefusal(status: Int) async {
        StubGitHub.answering([status, 200])
        let client = client(StubGitHub.session())

        await #expect(throws: GitHubError.self) {
            _ = try await client.get(self.rest)
        }
        #expect(StubGitHub.sent.count == 1)
    }

    @Test("A mutation is sent once, whatever the gateway says")
    func doesNotRepeatAMutation() async {
        StubGitHub.answering([502, 200])
        let client = client(StubGitHub.session())

        // A 502 says the gateway got no answer, not that nothing happened
        // behind it: a second send would be a second approval.
        await #expect(throws: GitHubError.self) {
            _ = try await client.graphQL(
                "mutation($id: ID!) { addPullRequestReview(input: { pullRequestId: $id }) { clientMutationId } }",
                variables: ["id": "PR_1"]
            )
        }
        #expect(StubGitHub.sent.count == 1)
    }

    @Test("A query is not a mutation and may be asked again")
    func repeatsAQuery() async throws {
        StubGitHub.answering([502, 200])
        _ = try await client(StubGitHub.session()).graphQL("query { viewer { login } }")

        #expect(StubGitHub.sent.count == 2)
    }

    @Test("Every attempt reaches the log, not just the last one")
    func recordsEveryAttempt() async throws {
        StubGitHub.answering([502, 200])
        let log = Log()
        _ = try await client(StubGitHub.session(), watch: { log.add($0) }).get(rest)

        // A log showing only the answer that worked would say the gateway
        // was fine, which is the opposite of what the tab is for.
        #expect(log.all.count == 2)
        #expect(log.all.first?.outcome == .answered(status: 502))
        #expect(log.all.last?.outcome == .answered(status: 200))
    }

    @Test("What may be sent again, and what may not")
    func repeatable() throws {
        var read = URLRequest(url: rest)
        read.httpMethod = "GET"
        #expect(GitHubClient.isRepeatable(read))

        var query = URLRequest(url: graphQL)
        query.httpMethod = "POST"
        query.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": "  query { viewer { login } }"]
        )
        #expect(GitHubClient.isRepeatable(query))

        var mutation = URLRequest(url: graphQL)
        mutation.httpMethod = "POST"
        mutation.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": "\nmutation($id: ID!) { markFileAsViewed { clientMutationId } }"]
        )
        #expect(!GitHubClient.isRepeatable(mutation))

        // Marking a notification read is harmless twice, but it is still a
        // write, and the rule is about what changes rather than about what
        // the damage would be.
        var write = URLRequest(url: rest)
        write.httpMethod = "PATCH"
        #expect(!GitHubClient.isRepeatable(write))
    }

    @Test("Two waits, both short enough to still be a refresh")
    func delays() {
        #expect(GitHubClient.defaultRetryDelays.count == 2)
        #expect(GitHubClient.defaultRetryDelays.allSatisfy { $0 <= .seconds(5) })
        #expect(GitHubClient.retryStatuses == [502, 503, 504])
    }
}
