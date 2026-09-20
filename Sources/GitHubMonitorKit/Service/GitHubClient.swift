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

    nonisolated(unsafe) private static let clockFormatter: DateFormatter = {
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

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Requests

    public func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await perform(request)
    }

    public func graphQL(_ document: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": document])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await perform(request)

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw GitHubError.decoding("response was not a JSON object")
        }
        // GraphQL reports failures with HTTP 200 and an "errors" array, so a
        // successful status code is not on its own a successful request.
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }
            throw GitHubError.graphQL(messages.isEmpty ? ["GraphQL request failed"] : messages)
        }
        guard let payload = root["data"] as? [String: Any] else {
            throw GitHubError.decoding("response contained no data")
        }
        return payload
    }

    @discardableResult
    public func patch(_ url: URL) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        return try await perform(request).1
    }

    // MARK: - Plumbing

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitHubMonitor", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.decoding("response was not HTTP")
        }

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
