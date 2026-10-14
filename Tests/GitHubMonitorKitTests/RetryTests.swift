import Foundation
import Testing

@testable import GitHubMonitorKit

/// A stand-in for GitHub, so what the client does with a gateway error can
/// be watched rather than reasoned about.
///
/// Each stub keeps its own script and hands out its own session, told apart
/// by a header that session adds to every request. Suites run beside one
/// another, and a script read by two of them is a script neither of them
/// wrote -- which showed up first as a test seeing a page it had never
/// written.
///
/// The requests it keeps carry no body: URLSession hands a protocol the body
/// as a stream. So nothing here asks what was posted, only how often.
final class StubGitHub: URLProtocol, @unchecked Sendable {
    /// One answer from a script: a status, and what came with it.
    struct Answer {
        var status: Int = 200
        var body: Data = Data(#"{"data":{}}"#.utf8)
    }

    /// One scripted GitHub: the session to give the client, and the record
    /// of what that client asked for.
    final class Stub: @unchecked Sendable {
        let session: URLSession
        fileprivate let id: String

        fileprivate init(id: String, session: URLSession) {
            self.id = id
            self.session = session
        }

        var sent: [URLRequest] { StubGitHub.sent(for: id) }

        deinit { StubGitHub.forget(id) }
    }

    private struct Script {
        var answers: [Answer] = []
        var sent: [URLRequest] = []
    }

    nonisolated(unsafe) private static var scripts: [String: Script] = [:]
    private static let lock = NSLock()
    private static let header = "X-Stub-Id"

    /// A GitHub answering with these, in order. Anything asked past the end
    /// of the script gets an empty 200, so a script is a statement about the
    /// beginning of a conversation rather than all of it.
    static func answering(_ answers: [Answer]) -> Stub {
        let id = UUID().uuidString
        lock.lock()
        scripts[id] = Script(answers: answers)
        lock.unlock()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubGitHub.self]
        configuration.httpAdditionalHeaders = [header: id]
        return Stub(id: id, session: URLSession(configuration: configuration))
    }

    /// The statuses alone, where what came back does not matter.
    static func answering(_ statuses: [Int]) -> Stub {
        answering(statuses.map { Answer(status: $0) })
    }

    private static func sent(for id: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return scripts[id]?.sent ?? []
    }

    private static func forget(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        scripts[id] = nil
    }

    private static func next(for request: URLRequest) -> Answer {
        lock.lock()
        defer { lock.unlock() }
        guard
            let id = request.value(forHTTPHeaderField: header),
            var script = scripts[id]
        else {
            // Loud rather than quiet: a request that arrived without its
            // script means the stub was wired up wrong, and a plain 200
            // would let the test pass on nothing.
            return Answer(status: 599, body: Data(#"{"message":"no script"}"#.utf8))
        }
        script.sent.append(request)
        let answer = script.answers.isEmpty ? Answer() : script.answers.removeFirst()
        scripts[id] = script
        return answer
    }

    static func session() -> URLSession {
        answering([Answer]()).session
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let answer = Self.next(for: request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
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

@Suite("A gateway that did not answer")
struct RetryTests {
    private let rest = URL(string: "https://api.github.com/notifications")!
    private let graphQL = URL(string: "https://api.github.com/graphql")!

    /// No waiting: how long the client waits is checked by reading the
    /// constant, not by sitting through it.
    private func client(
        _ stub: StubGitHub.Stub, watch: (@Sendable (RequestRecord) -> Void)? = nil
    ) -> GitHubClient {
        GitHubClient(
            token: "token", session: stub.session, watch: watch, retryDelays: [.zero, .zero]
        )
    }

    @Test("A 502 on a read is asked again, and the answer that follows is the one used")
    func sendsAReadAgain() async throws {
        let stub = StubGitHub.answering([502, 502, 200])
        let (_, response) = try await client(stub).get(rest)

        #expect(response.statusCode == 200)
        #expect(stub.sent.count == 3)
    }

    @Test("It gives up rather than keep asking")
    func stopsAsking() async {
        let stub = StubGitHub.answering([502, 502, 502, 200])
        let client = client(stub)

        await #expect(throws: GitHubError.self) {
            _ = try await client.get(self.rest)
        }
        // The first send and the two the delays allow, and no fourth: a
        // timed-out request draws points from the hour's allowance, so
        // asking forever is paid for twice.
        #expect(stub.sent.count == 3)
    }

    @Test("All three gateway statuses count", arguments: [502, 503, 504])
    func everyGatewayStatus(status: Int) async throws {
        let stub = StubGitHub.answering([status, 200])
        _ = try await client(stub).get(rest)

        #expect(stub.sent.count == 2)
    }

    @Test("A refusal that will say the same next time is asked once", arguments: [401, 404, 422])
    func doesNotRepeatARefusal(status: Int) async {
        let stub = StubGitHub.answering([status, 200])
        let client = client(stub)

        await #expect(throws: GitHubError.self) {
            _ = try await client.get(self.rest)
        }
        #expect(stub.sent.count == 1)
    }

    @Test("A mutation is sent once, whatever the gateway says")
    func doesNotRepeatAMutation() async {
        let stub = StubGitHub.answering([502, 200])
        let client = client(stub)

        // A 502 says the gateway got no answer, not that nothing happened
        // behind it: a second send would be a second approval.
        await #expect(throws: GitHubError.self) {
            _ = try await client.graphQL(
                "mutation($id: ID!) { addPullRequestReview(input: { pullRequestId: $id }) { clientMutationId } }",
                variables: ["id": "PR_1"]
            )
        }
        #expect(stub.sent.count == 1)
    }

    @Test("A query is not a mutation and may be asked again")
    func repeatsAQuery() async throws {
        let stub = StubGitHub.answering([502, 200])
        _ = try await client(stub).graphQL("query { viewer { login } }")

        #expect(stub.sent.count == 2)
    }

    @Test("Every attempt reaches the log, not just the last one")
    func recordsEveryAttempt() async throws {
        let stub = StubGitHub.answering([502, 200])
        let log = Log()
        _ = try await client(stub, watch: { log.add($0) }).get(rest)

        // A log showing only the answer that worked would say the gateway
        // had been fine, which is the opposite of what the tab is for.
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
        // write, and the rule is about what changes rather than about how
        // bad the second one would be.
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
