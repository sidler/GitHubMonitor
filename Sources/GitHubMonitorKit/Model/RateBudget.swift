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
    /// What the request behind this reading cost, as GitHub charged it.
    ///
    /// GitHub's own number rather than a difference worked out here: the
    /// app makes other requests between two refreshes, and subtracting one
    /// reading from the next would charge a refresh for whatever else
    /// happened in between. Where one reading stands for a run of requests
    /// -- a list fetch that paged -- this is their total.
    public let cost: Int

    public init(
        remaining: Int, limit: Int, resetAt: Date?, readAt: Date = .now, cost: Int = 0
    ) {
        self.remaining = remaining
        self.limit = limit
        self.resetAt = resetAt
        self.readAt = readAt
        self.cost = cost
    }

    /// The same reading, standing for a run of requests that cost this much
    /// altogether.
    public func costing(_ total: Int) -> RateBudget {
        RateBudget(
            remaining: remaining, limit: limit, resetAt: resetAt, readAt: readAt, cost: total
        )
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
///
/// Reported from what GitHub charged for the last refresh, not predicted
/// from the number of searches. The prediction that stood here said one
/// point per search, which was measured against a query whose searches
/// carried nothing nested; the lists now ask each row for its linked
/// issues, and measured against the same allowance a refresh costs rather
/// more than its searches suggest.
public enum RefreshCost {
    /// What that refresh comes to over an hour, at this interval.
    public static func pointsPerHour(refreshCost: Int, interval: TimeInterval) -> Int {
        guard interval > 0, refreshCost > 0 else { return 0 }
        return Int((3600 / interval).rounded()) * refreshCost
    }

    public static func sentence(
        lastRefreshCost: Int?, interval: TimeInterval, limit: Int = 5000
    ) -> String {
        guard let lastRefreshCost else {
            return "No refresh has finished yet, so there is nothing measured to report."
        }
        guard lastRefreshCost > 0 else {
            return "No list is being fetched, so nothing is being spent."
        }
        let perHour = pointsPerHour(refreshCost: lastRefreshCost, interval: interval)
        let minutes = Int((interval / 60).rounded())
        let points = lastRefreshCost == 1 ? "1 point" : "\(lastRefreshCost) points"
        return "The last refresh cost \(points), which GitHub charged. "
            + "One every \(minutes) minute\(minutes == 1 ? "" : "s") "
            + "is about \(perHour) of its \(limit) an hour."
    }
}
