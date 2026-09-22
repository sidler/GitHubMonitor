import Foundation

/// What the charts about one's own pull requests show.
public enum MyTrendMetric: String, CaseIterable, Codable, Sendable {
    case opened
    case hourOfDay
    case comments
    case commenters
    case merge

    public var title: String {
        switch self {
        case .opened: "Pull requests opened"
        case .hourOfDay: "When they open"
        case .comments: "Comments per pull request"
        case .commenters: "Who comments"
        case .merge: "Time to merge"
        }
    }

    public var explanation: String {
        switch self {
        case .opened: "Opened by you per period, whatever became of them."
        case .hourOfDay: "The hour each was opened, across the whole range."
        case .comments: "Conversation and review comments, counted per pull request you opened."
        case .commenters: "Who wrote them, across the whole range."
        case .merge: "From ready for review to the merge, by the week it merged."
        }
    }
}

/// One period of one's own pull requests.
///
/// Counted by the event each number is about: opened, comments and the hour
/// of day belong to the pull requests opened in the period, the merge time
/// to those merged in it. Mixing the two would make a period's numbers
/// describe two different sets of pull requests.
public struct MyTrendBucket: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { start }
    public let start: Date
    public let end: Date

    public let opened: Int
    /// Hour of day (0-23) to how many pull requests were opened in it.
    public let hours: [Int: Int]
    /// Comments per pull request: fewest, middle and most.
    public let commentsFromPeople: TrendPoint
    public let commentsFromEveryone: TrendPoint
    /// Login to how many comments they wrote, bots kept apart.
    public let commentersFromPeople: [String: Int]
    public let commentersFromEveryone: [String: Int]
    /// Time from ready for review to the merge, for those merged here.
    public let merge: TrendPoint

    public init(
        start: Date,
        end: Date,
        opened: Int,
        hours: [Int: Int],
        commentsFromPeople: TrendPoint,
        commentsFromEveryone: TrendPoint,
        commentersFromPeople: [String: Int],
        commentersFromEveryone: [String: Int],
        merge: TrendPoint
    ) {
        self.start = start
        self.end = end
        self.opened = opened
        self.hours = hours
        self.commentsFromPeople = commentsFromPeople
        self.commentsFromEveryone = commentsFromEveryone
        self.commentersFromPeople = commentersFromPeople
        self.commentersFromEveryone = commentersFromEveryone
        self.merge = merge
    }

    public func comments(includingBots: Bool) -> TrendPoint {
        includingBots ? commentsFromEveryone : commentsFromPeople
    }

    public func commenters(includingBots: Bool) -> [String: Int] {
        includingBots ? commentersFromEveryone : commentersFromPeople
    }
}

/// One person's pull request history, as far as it has been read.
public struct MyTrendData: Codable, Hashable, Sendable {
    public static let schema = 1

    public let schema: Int
    /// Whose pull requests these are.
    public let login: String
    public let resolution: TrendResolution
    public var buckets: [MyTrendBucket]
    public var fetchedAt: Date
    public var truncationReason: String?

    public init(
        login: String,
        resolution: TrendResolution,
        buckets: [MyTrendBucket] = [],
        fetchedAt: Date = .now,
        truncationReason: String? = nil
    ) {
        self.schema = Self.schema
        self.login = login
        self.resolution = resolution
        self.buckets = buckets
        self.fetchedAt = fetchedAt
        self.truncationReason = truncationReason
    }

    public var isStale: Bool { Date.now.timeIntervalSince(fetchedAt) > TrendData.maximumAge }
    public var isComplete: Bool { buckets.count == resolution.bucketCount }

    /// The hours of the whole range, summed.
    ///
    /// A single period holds far too few pull requests to say anything about
    /// habits; the shape only appears across the range.
    public var hours: [Int: Int] {
        buckets.reduce(into: [:]) { total, bucket in
            for (hour, count) in bucket.hours { total[hour, default: 0] += count }
        }
    }

    /// Who commented across the whole range, most first.
    public func commenters(includingBots: Bool) -> [(login: String, comments: Int)] {
        let totals = buckets.reduce(into: [String: Int]()) { total, bucket in
            for (login, count) in bucket.commenters(includingBots: includingBots) {
                total[login, default: 0] += count
            }
        }
        return totals
            .map { (login: $0.key, comments: $0.value) }
            .sorted {
                $0.comments == $1.comments
                    ? $0.login.localizedStandardCompare($1.login) == .orderedAscending
                    : $0.comments > $1.comments
            }
    }

    public var totalOpened: Int { buckets.reduce(0) { $0 + $1.opened } }
}

/// Lifecycle of the personal trends fetch.
public enum MyTrendState: Equatable, Sendable {
    /// No token yet, so nobody to report on.
    case unconfigured
    case loading(MyTrendData?)
    case loaded(MyTrendData)
    case failed(String)

    public var data: MyTrendData? {
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
