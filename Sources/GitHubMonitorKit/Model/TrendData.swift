import Foundation

/// How wide one point on the trend charts is.
public enum TrendResolution: String, CaseIterable, Codable, Sendable {
    case weekly
    case monthly

    public var label: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    /// A quarter in weeks, a year in months: both fit across a chart without
    /// crowding the axis, and both bound how much history is fetched.
    public var bucketCount: Int { 12 }

    var component: Calendar.Component {
        switch self {
        case .weekly: .weekOfYear
        case .monthly: .month
        }
    }
}

/// What the five charts show.
public enum TrendMetric: String, CaseIterable, Codable, Sendable {
    case firstReview
    case approval
    case approvalToMerge
    case merge
    case volume

    public var title: String {
        switch self {
        case .firstReview: "Time to first review"
        case .approval: "Time to approval"
        case .approvalToMerge: "Approval to merge"
        case .merge: "Time to merge"
        case .volume: "Pull requests"
        }
    }

    /// What the number means, since every one of these could be measured
    /// half a dozen ways.
    public var explanation: String {
        switch self {
        case .firstReview:
            "From ready for review to the first review by another person. Bots do not count."
        case .approval:
            "From ready for review to the last approval before the merge."
        case .approvalToMerge:
            "From that approval to the merge — how long a finished pull request waits."
        case .merge:
            "From ready for review to the merge."
        case .volume:
            "Opened and merged per period, counted by the day each happened."
        }
    }

    public var isDuration: Bool { self != .volume }
}

/// What one period's pull requests took: the middle of them, the two ends,
/// and how many there were.
///
/// The count travels with the values because a median of two says something
/// very different from a median of forty, and the chart cannot show that on
/// its own. The ends travel with it because the middle alone does not say
/// whether the period was even, or whether one pull request sat for a month
/// while the rest went through in an hour.
public struct TrendPoint: Codable, Hashable, Sendable {
    /// Seconds. Nil where no pull request in the period reached this stage,
    /// which is a gap in the line rather than a zero.
    public let median: TimeInterval?
    public let fastest: TimeInterval?
    public let slowest: TimeInterval?
    public let samples: Int

    public static let none = TrendPoint(median: nil, fastest: nil, slowest: nil, samples: 0)

    public init(median: TimeInterval?, fastest: TimeInterval?, slowest: TimeInterval?, samples: Int) {
        self.median = median
        self.fastest = fastest
        self.slowest = slowest
        self.samples = samples
    }

    public func value(for line: TrendLine) -> TimeInterval? {
        switch line {
        case .fastest: fastest
        case .median: median
        case .slowest: slowest
        }
    }
}

/// The three lines a duration chart draws.
public enum TrendLine: String, CaseIterable, Sendable {
    case fastest
    case median
    case slowest

    /// Named for what they are, not for the statistic: "slowest" is the
    /// pull request that took longest, and that is the word for it.
    public var label: String {
        switch self {
        case .fastest: "Fastest"
        case .median: "Median"
        case .slowest: "Slowest"
        }
    }
}

/// Everything one period reports, for one audience.
public struct TrendValues: Codable, Hashable, Sendable {
    public let opened: Int
    public let merged: Int
    public let firstReview: TrendPoint
    public let approval: TrendPoint
    public let approvalToMerge: TrendPoint
    public let merge: TrendPoint

    public static let none = TrendValues(
        opened: 0, merged: 0,
        firstReview: .none, approval: .none, approvalToMerge: .none, merge: .none
    )

    public init(
        opened: Int,
        merged: Int,
        firstReview: TrendPoint,
        approval: TrendPoint,
        approvalToMerge: TrendPoint,
        merge: TrendPoint
    ) {
        self.opened = opened
        self.merged = merged
        self.firstReview = firstReview
        self.approval = approval
        self.approvalToMerge = approvalToMerge
        self.merge = merge
    }

    public func point(for metric: TrendMetric) -> TrendPoint {
        switch metric {
        case .firstReview: firstReview
        case .approval: approval
        case .approvalToMerge: approvalToMerge
        case .merge: merge
        case .volume: TrendPoint(median: nil, fastest: nil, slowest: nil, samples: merged)
        }
    }
}

/// One period of the chart.
///
/// Both audiences are computed and kept, since they come out of the same
/// pull requests: hiding the bots is then a redraw rather than another trip
/// to GitHub.
public struct TrendBucket: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    /// Everything except pull requests opened by bot accounts.
    public let people: TrendValues
    public let everyone: TrendValues

    public init(start: Date, end: Date, people: TrendValues, everyone: TrendValues) {
        self.start = start
        self.end = end
        self.people = people
        self.everyone = everyone
    }

    public func values(includingBots: Bool) -> TrendValues {
        includingBots ? everyone : people
    }
}

/// A repository's history, as far as it has been read.
public struct TrendData: Codable, Hashable, Sendable {
    /// Raised whenever a stored history stops meaning what it did. A file
    /// from before is not read, so a definition that changed cannot go on
    /// being drawn as though it had not.
    public static let schema = 2

    public let schema: Int
    public let repository: String
    public let resolution: TrendResolution
    /// Oldest first. Grows as the periods come in, so the charts can be
    /// drawn before the whole history has arrived.
    public var buckets: [TrendBucket]
    public var fetchedAt: Date
    /// Set when the fetch stopped early -- the quota ran low, or a request
    /// failed -- so the charts can say that they are incomplete rather than
    /// quietly showing less.
    public var truncationReason: String?

    public init(
        repository: String,
        resolution: TrendResolution,
        buckets: [TrendBucket] = [],
        fetchedAt: Date = .now,
        truncationReason: String? = nil
    ) {
        self.schema = Self.schema
        self.repository = repository
        self.resolution = resolution
        self.buckets = buckets
        self.fetchedAt = fetchedAt
        self.truncationReason = truncationReason
    }

    /// How long a cached history is worth showing before it is fetched
    /// again. A quarter's trend does not move in an afternoon.
    public static let maximumAge: TimeInterval = 6 * 3600

    public var isStale: Bool { Date.now.timeIntervalSince(fetchedAt) > Self.maximumAge }

    public var isComplete: Bool { buckets.count == resolution.bucketCount }
}

/// Lifecycle of the trends fetch.
public enum TrendState: Equatable, Sendable {
    /// No repository chosen yet.
    case unconfigured
    /// Nothing to show yet; the periods are still coming in.
    case loading(TrendData?)
    case loaded(TrendData)
    case failed(String)

    /// Whatever there is to draw, loaded or still filling.
    public var data: TrendData? {
        switch self {
        case .loading(let data): data
        case .loaded(let data): data
        case .unconfigured, .failed: nil
        }
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
