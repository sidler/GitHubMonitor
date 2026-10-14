import Foundation

public enum GitHubError: Error, LocalizedError, Equatable {
    case noToken
    case unauthorized
    case forbidden(String)
    /// Rate limit exhausted; carries the time the window resets.
    case rateLimited(until: Date?)
    case missingScopes([String])
    case http(status: Int, message: String)
    case graphQL([String])
    case transport(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .noToken:
            "No GitHub token configured"
        case .unauthorized:
            "Token rejected — it may have expired or been revoked"
        case .forbidden(let message):
            "Access denied: \(message)"
        case .rateLimited(let until):
            // Deliberately an absolute time rather than "in 12 minutes": this
            // string is produced off the main actor, where the shared relative
            // formatter is not reachable, and a wall clock time is clearer in
            // an error anyway.
            if let until {
                "Rate limit reached, resets at \(Self.clockFormatter.string(from: until))"
            } else {
                "Rate limit reached"
            }
        case .missingScopes(let scopes):
            "Token is missing: \(scopes.joined(separator: ", "))"
        case .http(let status, let message):
            message.isEmpty ? "GitHub returned \(status)" : "GitHub returned \(status): \(message)"
        case .graphQL(let messages):
            messages.first ?? "GraphQL request failed"
        case .transport(let message):
            "Network error: \(message)"
        case .decoding(let message):
            "Unexpected response: \(message)"
        }
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Whether retrying on the next tick could plausibly succeed. An expired
    /// token will not fix itself; a flaky network might.
    public var isTransient: Bool {
        switch self {
        case .transport, .rateLimited, .http: true
        case .noToken, .unauthorized, .forbidden, .missingScopes, .graphQL, .decoding: false
        }
    }
}

/// Thin HTTP layer over GitHub's REST and GraphQL endpoints.
///
/// A value type rather than an actor: it holds nothing mutable, and an actor
/// boundary would force every JSON payload to be Sendable for no benefit.
public struct GitHubClient: Sendable {
    private let token: String
    private let session: URLSession
    /// Told about every request and what came back, so a run of gateway
    /// errors can be looked at rather than guessed at. Set by whoever
    /// builds the client; nil leaves the client as it was.
    private let watch: (@Sendable (RequestRecord) -> Void)?
    /// How long to wait before each further attempt. A property rather
    /// than the constant itself because it is policy, not law -- and
    /// because a test for the retrying should not take four seconds to
    /// find out that it works.
    private let retryDelays: [Duration]

    public init(
        token: String,
        session: URLSession = .shared,
        watch: (@Sendable (RequestRecord) -> Void)? = nil,
        retryDelays: [Duration] = GitHubClient.defaultRetryDelays
    ) {
        self.watch = watch
        self.token = token
        self.session = session
        self.retryDelays = retryDelays
    }

    // MARK: - Requests

    public func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await perform(request)
    }

    public func graphQL(
        _ document: String,
        variables: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let answer = try await graphQLAnswer(document, variables: variables)
        // GraphQL reports failures with HTTP 200 and an "errors" array, so a
        // successful status code is not on its own a successful request.
        if !answer.failures.isEmpty {
            throw GitHubError.graphQL(answer.failures.map(\.message))
        }
        return answer.data
    }

    /// The same request, with whatever failed handed back rather than
    /// thrown.
    ///
    /// A document that asks several things at once -- which is how the
    /// lists travel, all of them in one request -- gets an answer for the
    /// ones that worked and an error for the one that did not. Throwing
    /// discards the answer along with the error, so one list written with a
    /// qualifier GitHub will not take stopped every other list from
    /// refreshing.
    public func graphQLAnswer(
        _ document: String,
        variables: [String: Any]? = nil
    ) async throws -> GraphQLAnswer {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        var body: [String: Any] = ["query": document]
        if let variables { body["variables"] = variables }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await perform(request)

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw GitHubError.decoding("response was not a JSON object")
        }

        let failures = GraphQLAnswer.failures(from: root)
        guard let payload = root["data"] as? [String: Any] else {
            // No data at all: there is nothing to carry on with, so this is
            // a failure however it is reported.
            if !failures.isEmpty { throw GitHubError.graphQL(failures.map(\.message)) }
            throw GitHubError.decoding("response contained no data")
        }
        return GraphQLAnswer(data: payload, failures: failures)
    }

    @discardableResult
    /// A picture from a body, which GitHub answers for by sending
    /// somebody else's address.
    ///
    /// Its own call because of what happens after the first answer: the
    /// redirect goes to a host that is not GitHub, and two things have to
    /// be true before it is followed. See `following(_:from:)`.
    public func image(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return try await perform(request, delegate: ImageRedirect()).0
    }

    /// What to send when a picture's address redirects somewhere else.
    ///
    /// Two repairs, both of which otherwise end in a picture that never
    /// arrives for a reason nothing reports.
    ///
    /// The address GitHub sends back is HTML-escaped: the ampersands
    /// between the parts of the query come through as `&amp;`, so every
    /// parameter after the first is called `amp;X-Amz-Something` and the
    /// signature covers a request nobody made.
    ///
    /// And the token goes no further than GitHub. What a picture
    /// redirects to is somebody else's host, and the account's
    /// credential is not theirs to see. Amazon refuses it in any case: a
    /// signed address and an Authorization header together are two
    /// authorities where it expects one.
    static func following(_ request: URLRequest, from origin: URL?) -> URLRequest {
        var next = request
        if let url = next.url,
            url.absoluteString.contains("&amp;"),
            let repaired = URL(
                string: url.absoluteString.replacingOccurrences(of: "&amp;", with: "&")
            ) {
            next.url = repaired
        }
        if next.url?.host != origin?.host {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return next
    }

    public func patch(_ url: URL) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        return try await perform(request).1
    }

    // MARK: - Plumbing

    /// The statuses worth sending again.
    ///
    /// All three say the same thing: the gateway did not get an answer
    /// from what is behind it. That is a statement about this moment, not
    /// about the request -- unlike a 401 or a 422, which will say the
    /// same thing however often they are asked.
    static let retryStatuses: Set<Int> = [502, 503, 504]

    /// How long to wait before each further attempt, and by its length,
    /// how many there are.
    ///
    /// Two, not five. GitHub ends any request that runs past ten seconds
    /// with a 502 or a 504, and since July 2025 a request that timed out
    /// also draws extra points from the hour's allowance -- so sending
    /// the same expensive query over and over is paid for twice and
    /// likely to time out again at the same place. These two cover the
    /// gateway that was merely having a moment; past that the error is
    /// the honest answer.
    public static let defaultRetryDelays: [Duration] = [.seconds(1), .seconds(3)]

    /// Whether sending this request again could only repeat work, never
    /// double it.
    ///
    /// A 502 says the gateway got no answer, not that nothing happened
    /// behind it. Approving a pull request twice leaves two approvals, so
    /// only requests that change nothing are sent again: reads, and the
    /// GraphQL documents that are not mutations.
    static func isRepeatable(_ request: URLRequest) -> Bool {
        switch request.httpMethod ?? "GET" {
        case "GET":
            return true
        case "POST":
            // Everything the app posts goes to /graphql; anything else
            // arriving here is new and should opt in deliberately.
            guard request.url?.path.hasSuffix("/graphql") == true else { return false }
            guard
                let body = request.httpBody,
                let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                let query = root["query"] as? String
            else { return false }
            return !query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("mutation")
        default:
            return false
        }
    }

    private func perform(
        _ request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Only where the caller has not said what it wants. A picture is
        // not JSON, and saying so to the host that serves it costs
        // nothing where it is ignored.
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitHubMonitor", forHTTPHeaderField: "User-Agent")

        var delays: ArraySlice<Duration> = Self.isRepeatable(request) ? retryDelays[...] : []
        while true {
            do {
                return try await attempt(request, delegate: delegate)
            } catch let failure as GitHubError {
                guard
                    case .http(let status, _) = failure,
                    Self.retryStatuses.contains(status),
                    let wait = delays.first
                else { throw failure }
                delays = delays.dropFirst()
                // Waiting is also where a cancelled refresh notices that
                // it was cancelled; waking up to send another request
                // would be the one thing it must not do.
                do {
                    try await Task.sleep(for: wait)
                } catch {
                    throw failure
                }
            }
        }
    }

    /// One send. Every attempt is recorded, including the ones that were
    /// followed by another: a log that showed only the last of three
    /// would say the gateway answered first time.
    private func attempt(
        _ request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let started = Date()
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "?"
        let operation = Self.operation(of: request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: delegate)
        } catch {
            watch?(RequestRecord(
                startedAt: started, method: method, path: path, operation: operation,
                outcome: .failed(error.localizedDescription),
                duration: Date().timeIntervalSince(started)
            ))
            throw GitHubError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.decoding("response was not HTTP")
        }

        // Recorded whatever the answer was. A log holding only the
        // failures cannot say whether anything was working in between,
        // which is the first question about an intermittent one.
        let trouble = http.statusCode >= 400
        watch?(RequestRecord(
            startedAt: started, method: method, path: path, operation: operation,
            outcome: .answered(status: http.statusCode),
            duration: Date().timeIntervalSince(started),
            bytes: data.count,
            remaining: http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init),
            body: trouble ? Self.excerpt(of: data) : nil
        ))

        switch http.statusCode {
        case 200..<300, 304:
            return (data, http)
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            // GitHub signals both "forbidden" and "rate limited" with 403; the
            // remaining-requests header is what tells them apart.
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw GitHubError.rateLimited(until: Self.rateLimitReset(from: http))
            }
            throw GitHubError.forbidden(Self.message(from: data) ?? "no reason given")
        default:
            throw GitHubError.http(status: http.statusCode, message: Self.message(from: data) ?? "")
        }
    }

    /// Which document a GraphQL request carries.
    ///
    /// They all post to the same path, so without this every one of them
    /// reads the same in the log. Taken from the query's own first field
    /// -- `search`, `repository`, `viewer` -- which is as much as is
    /// needed to tell one call from another, and carries no values.
    static func operation(of request: URLRequest) -> String? {
        guard request.url?.path.hasSuffix("/graphql") == true else { return nil }
        guard
            let body = request.httpBody,
            let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let query = root["query"] as? String
        else { return "graphql" }

        guard let open = query.firstIndex(of: "{") else { return "graphql" }
        let rest = query[query.index(after: open)...]
            .drop { $0.isWhitespace || $0.isNewline }
        let field = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return field.isEmpty ? "graphql" : "graphql \(field)"
    }

    /// The first part of what came back, for a line in the log.
    ///
    /// Trimmed because a gateway error can answer with a whole HTML page,
    /// and the part naming what failed is at the top of it.
    static func excerpt(of data: Data, limit: Int = 400) -> String? {
        guard let text = String(data: data, encoding: .utf8) else {
            return data.isEmpty ? nil : "\(data.count) bytes, not text"
        }
        let tidy = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !tidy.isEmpty else { return nil }
        return tidy.count > limit ? String(tidy.prefix(limit)) + "\u{2026}" : tidy
    }

    /// What the REST headers say is left of the hourly allowance.
    static func budget(from response: HTTPURLResponse) -> RateBudget? {
        guard
            let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init),
            let limit = response.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init)
        else { return nil }
        return RateBudget(remaining: remaining, limit: limit, resetAt: rateLimitReset(from: response))
    }

    static func rateLimitReset(from response: HTTPURLResponse) -> Date? {
        guard
            let raw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
            let seconds = TimeInterval(raw)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func message(from data: Data) -> String? {
        guard
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let message = object["message"] as? String
        else { return nil }
        return message
    }
}

/// What one GraphQL request came back with: what worked, and what did not.
///
/// Not `Sendable`: the payload is the parsed JSON, whose values are `Any`.
/// It is read on the actor that asked for it, as every other payload in
/// this file is.
public struct GraphQLAnswer {
    /// One thing GitHub refused, and where in the document it was asked.
    public struct Failure: Equatable, Sendable {
        public let message: String
        /// The aliases leading to the field that failed, as GitHub reports
        /// them -- `["s3"]` for the fourth search in a batch. Empty where
        /// the failure belongs to the request as a whole.
        public let path: [String]

        public init(message: String, path: [String]) {
            self.message = message
            self.path = path
        }
    }

    public let data: [String: Any]
    public let failures: [Failure]

    public init(data: [String: Any], failures: [Failure]) {
        self.data = data
        self.failures = failures
    }

    static func failures(from root: [String: Any]) -> [Failure] {
        guard let errors = root["errors"] as? [[String: Any]] else { return [] }
        return errors.map { entry in
            Failure(
                message: entry["message"] as? String ?? "GitHub refused the request",
                // Numbers appear in a path into a list; only the names
                // matter for finding which search it was.
                path: (entry["path"] as? [Any] ?? []).compactMap { $0 as? String }
            )
        }
    }
}


/// Follows a picture's redirect, repaired and without the account's token.
///
/// A class because that is what `URLSession` asks for; it holds nothing
/// and decides nothing -- `GitHubClient.following(_:from:)` does, where it
/// can be read and tested without a network.
final class ImageRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        GitHubClient.following(request, from: task.originalRequest?.url)
    }
}
