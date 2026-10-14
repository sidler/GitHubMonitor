import Foundation

/// One request to GitHub and what came back.
///
/// Kept so that a run of 502s can be looked at rather than guessed at:
/// when they started, which call they hit, whether anything succeeded in
/// between, and what GitHub actually said. A gateway error carries a body
/// naming the part of GitHub that failed, and that body is otherwise
/// thrown away with the error.
public struct RequestRecord: Identifiable, Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case answered(status: Int)
        /// Nothing came back at all: no network, a timeout, a dropped
        /// connection. There is no status to show for these.
        case failed(String)

        public var isTrouble: Bool {
            switch self {
            case .answered(let status): status >= 400
            case .failed: true
            }
        }
    }

    public let id: UUID
    public let startedAt: Date
    public let method: String
    /// The path, without the host. Every one of these goes to the same
    /// place and the host would be the longest part of every line.
    public let path: String
    /// For GraphQL, which of the documents it was: they all post to
    /// `/graphql`, so the path alone says nothing.
    public let operation: String?
    public let outcome: Outcome
    public let duration: TimeInterval
    public let bytes: Int
    /// What the hourly allowance had left, where the answer said.
    public let remaining: Int?
    /// What GitHub sent back, kept only where something went wrong and
    /// trimmed: a 502's body names the service that failed, and that is
    /// the one thing worth reading.
    public let body: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        method: String,
        path: String,
        operation: String? = nil,
        outcome: Outcome,
        duration: TimeInterval,
        bytes: Int = 0,
        remaining: Int? = nil,
        body: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.method = method
        self.path = path
        self.operation = operation
        self.outcome = outcome
        self.duration = duration
        self.bytes = bytes
        self.remaining = remaining
        self.body = body
    }

    /// What a line in the list says.
    public var status: String {
        switch outcome {
        case .answered(let status): "\(status)"
        case .failed: "\u{2014}"
        }
    }

    public var what: String { operation ?? path }

    /// What went wrong, from wherever it was kept: the body GitHub sent
    /// with a refusal, or the reason nothing arrived at all.
    public var said: String? {
        if let body, !body.isEmpty { return body }
        if case .failed(let reason) = outcome { return reason }
        return nil
    }
}

/// The last few hundred requests, newest last.
///
/// A fixed number rather than a fixed age: a quiet morning should still
/// have the morning's requests in it, and a storm of retries should not
/// push a week of them out of memory. Nothing is written to disk — this
/// answers "what is happening now", and a log that outlives the question
/// is a file nobody asked for carrying somebody's repository names.
public struct RequestLog: Sendable {
    public private(set) var records: [RequestRecord] = []
    public let limit: Int

    public init(limit: Int = 300) {
        self.limit = limit
    }

    public mutating func add(_ record: RequestRecord) {
        records.append(record)
        if records.count > limit { records.removeFirst(records.count - limit) }
    }

    public mutating func clear() { records.removeAll() }

    /// Newest first, which is the order anybody reads a log in.
    public var newestFirst: [RequestRecord] {
        records.sorted { $0.startedAt > $1.startedAt }
    }

    public var troubles: Int {
        records.count { $0.outcome.isTrouble }
    }

    /// The whole thing as text, for pasting into a report.
    ///
    /// Its own formatter rather than `RelativeTime`'s, which belongs to
    /// the main actor: a transcript is built where the button is pressed
    /// and nowhere else needs to wait for that.
    public func transcript() -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm:ss.SSS"

        return newestFirst.map { record in
            var line = [
                clock.string(from: record.startedAt),
                record.status,
                record.method,
                record.what,
                String(format: "%.0fms", record.duration * 1000),
            ]
            if let remaining = record.remaining { line.append("\(remaining) left") }
            var text = line.joined(separator: "  ")
            // What went wrong, wherever it is kept. A transport failure
            // has no body and no status -- its reason is the only thing
            // the line carries, and leaving it out made the most
            // interesting row the emptiest one.
            if let said = record.said {
                text += "\n    " + said.replacingOccurrences(of: "\n", with: "\n    ")
            }
            return text
        }
        .joined(separator: "\n")
    }
}
