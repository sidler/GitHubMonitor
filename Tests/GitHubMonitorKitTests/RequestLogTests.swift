import Foundation
import Testing
@testable import GitHubMonitorKit

/// What the Requests tab is built on.
@Suite("A log of what GitHub was asked and what it said")
struct RequestLogTests {
    private func record(
        _ status: Int?, at seconds: TimeInterval, path: String = "/notifications"
    ) -> RequestRecord {
        RequestRecord(
            startedAt: Date(timeIntervalSince1970: seconds),
            method: "GET",
            path: path,
            outcome: status.map { .answered(status: $0) } ?? .failed("the network went away"),
            duration: 0.123
        )
    }

    /// A fixed number rather than a fixed age: a storm of retries must not
    /// push the morning out of memory, and a quiet morning should still
    /// have the morning in it.
    @Test("It keeps the newest and lets the oldest go")
    func bounded() {
        var log = RequestLog(limit: 3)
        for second in 1...5 { log.add(record(200, at: Double(second))) }

        #expect(log.records.count == 3)
        #expect(log.newestFirst.first?.startedAt == Date(timeIntervalSince1970: 5))
        #expect(log.newestFirst.last?.startedAt == Date(timeIntervalSince1970: 3))
    }

    /// Records arrive from requests that finish in whatever order they
    /// finish, so the order they were started in is the one to read.
    @Test("It reads newest first however they arrived")
    func ordered() {
        var log = RequestLog()
        log.add(record(200, at: 30))
        log.add(record(502, at: 10))
        log.add(record(200, at: 20))

        #expect(log.newestFirst.map(\.startedAt.timeIntervalSince1970) == [30, 20, 10])
    }

    @Test("What counts as trouble")
    func trouble() {
        var log = RequestLog()
        log.add(record(200, at: 1))
        log.add(record(304, at: 2))
        log.add(record(502, at: 3))
        log.add(record(nil, at: 4))

        #expect(log.troubles == 2)
        // A 304 is a success: the poll cost nothing because nothing moved.
        #expect(!RequestRecord.Outcome.answered(status: 304).isTrouble)
        #expect(RequestRecord.Outcome.answered(status: 503).isTrouble)
        #expect(RequestRecord.Outcome.failed("timed out").isTrouble)
    }

    @Test("The transcript carries the time, the status and what was said")
    func transcript() {
        var log = RequestLog()
        log.add(RequestRecord(
            startedAt: Date(timeIntervalSince1970: 0),
            method: "POST", path: "/graphql", operation: "graphql search",
            outcome: .answered(status: 502), duration: 1.5, bytes: 90,
            remaining: 4_980, body: "Our services are not available"
        ))

        let text = log.transcript()
        #expect(text.contains("502"))
        #expect(text.contains("graphql search"))
        #expect(text.contains("1500ms"))
        #expect(text.contains("4980 left"))
        #expect(text.contains("Our services are not available"))
    }

    /// The row with no status is the one somebody is looking for, and its
    /// reason is the only thing it carries.
    @Test("A transport failure takes its reason into the transcript")
    func reasonTravels() {
        var log = RequestLog()
        log.add(record(nil, at: 1, path: "/repos/octo/server/pulls/482/files"))

        let text = log.transcript()
        #expect(text.contains("the network went away"))
        #expect(text.contains("/repos/octo/server/pulls/482/files"))
    }

    @Test("Clearing empties it")
    func cleared() {
        var log = RequestLog()
        log.add(record(200, at: 1))
        log.clear()
        #expect(log.records.isEmpty)
        #expect(log.transcript().isEmpty)
    }
}

/// How a request describes itself in the log.
@Suite("Telling one call from another")
struct RequestNamingTests {
    private func graphQL(_ query: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        return request
    }

    /// Every GraphQL call posts to the same path, so without this they all
    /// read the same in a log.
    @Test("A GraphQL request is named by the field it asks for")
    func operations() {
        #expect(
            GitHubClient.operation(of: graphQL("query { search(first: 10) { nodes { id } } }"))
                == "graphql search"
        )
        #expect(
            GitHubClient.operation(of: graphQL("query($o: String!) {\n  repository(owner: $o) { id }\n}"))
                == "graphql repository"
        )
        #expect(GitHubClient.operation(of: graphQL("not a query")) == "graphql")
    }

    /// A REST call says what it is in its path already.
    @Test("A REST request is not given one")
    func restHasNone() {
        let request = URLRequest(url: URL(string: "https://api.github.com/notifications")!)
        #expect(GitHubClient.operation(of: request) == nil)
    }

    /// A gateway error can answer with a whole page, and the part naming
    /// what failed is at the top of it.
    @Test("What came back is trimmed to something readable")
    func excerpt() {
        let long = String(repeating: "x", count: 900)
        let cut = GitHubClient.excerpt(of: Data(long.utf8), limit: 40)
        #expect(cut?.count == 41)
        #expect(cut?.hasSuffix("\u{2026}") == true)

        #expect(
            GitHubClient.excerpt(of: Data("  several   lines\nof  it ".utf8))
                == "several lines of it"
        )
        #expect(GitHubClient.excerpt(of: Data()) == nil)
        #expect(GitHubClient.excerpt(of: Data([0xFF, 0xFE])) == "2 bytes, not text")
    }
}
