import Foundation

/// What is left of one of GitHub's hourly allowances.
///
/// Two of them, kept apart: GraphQL and REST have an allowance each, and a
/// single number covering both would be an invention. The lists and the
/// charts spend the first; the mentions spend the second.
public struct RateBudget: Equatable, Sendable {
    public let remaining: Int
    public let limit: Int
    /// When the allowance is restored. Nil where GitHub did not say, which
    /// the GraphQL answer sometimes does not.
    public let resetAt: Date?
    public let readAt: Date

    public init(remaining: Int, limit: Int, resetAt: Date?, readAt: Date = .now) {
        self.remaining = remaining
        self.limit = limit
        self.resetAt = resetAt
        self.readAt = readAt
    }

    public var fraction: Double {
        limit > 0 ? Double(remaining) / Double(limit) : 0
    }

    /// Low enough to say something about, but not yet low enough to stop
    /// for. The same number the chart fetches already stop at, so there is
    /// one idea here rather than two.
    public static let warningFloor = 500
    /// Low enough to stop refreshing the lists, leaving room for whatever is
    /// already in flight.
    public static let pauseFloor = 100

    public var isLow: Bool { remaining < Self.warningFloor }
    public var isExhausted: Bool { remaining < Self.pauseFloor }

    /// Whether the allowance has been restored since it was read, in which
    /// case what we know is stale and worth nothing.
    public func isStale(asOf now: Date = .now) -> Bool {
        guard let resetAt else { return now.timeIntervalSince(readAt) > 3600 }
        return now >= resetAt
    }
}

/// Both allowances, as last seen.
public struct RateBudgets: Equatable, Sendable {
    public var graphQL: RateBudget?
    public var rest: RateBudget?

    public init(graphQL: RateBudget? = nil, rest: RateBudget? = nil) {
        self.graphQL = graphQL
        self.rest = rest
    }

    /// The one worth warning about: whichever has least left, ignoring what
    /// has already been restored.
    public func pressing(asOf now: Date = .now) -> RateBudget? {
        [graphQL, rest]
            .compactMap { $0 }
            .filter { !$0.isStale(asOf: now) && $0.isLow }
            .min { $0.remaining < $1.remaining }
    }

    /// Whether the lists should sit this refresh out.
    public func shouldPause(asOf now: Date = .now) -> Bool {
        guard let graphQL, !graphQL.isStale(asOf: now) else { return false }
        return graphQL.isExhausted
    }
}

/// What the lists cost to keep up to date, for the sentence in Settings.
public enum RefreshCost {
    /// A search is one point, so a refresh costs one per line of every list
    /// that is shown somewhere.
    public static func pointsPerHour(searchLines: Int, interval: TimeInterval) -> Int {
        guard interval > 0, searchLines > 0 else { return 0 }
        return Int((3600 / interval).rounded()) * searchLines
    }

    public static func sentence(searchLines: Int, interval: TimeInterval, limit: Int = 5000) -> String {
        guard searchLines > 0 else {
            return "No list is being fetched, so nothing is being spent."
        }
        let perHour = pointsPerHour(searchLines: searchLines, interval: interval)
        let lines = searchLines == 1 ? "1 search" : "\(searchLines) searches"
        let minutes = Int((interval / 60).rounded())
        return "\(lines) every \(minutes) minute\(minutes == 1 ? "" : "s") "
            + "is about \(perHour) of GitHub's \(limit) points an hour."
    }
}
