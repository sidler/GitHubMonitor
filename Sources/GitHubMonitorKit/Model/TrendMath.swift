import Foundation

/// The timestamps one merged pull request contributes.
///
/// Extracted from the payload before any arithmetic, so the rules about
/// what counts -- whose reviews, which approval, when the clock starts --
/// live in one place and can be tested without a network.
public struct PullRequestTiming: Hashable, Sendable {
    /// Opened by a bot account. Kept rather than filtered out here, because
    /// both audiences are computed from the same fetch.
    public let isBot: Bool
    /// When the pull request started asking for attention: the moment it
    /// left draft, or when it was opened if it never was one. A pull request
    /// that sat as a draft for a week was not waiting on anybody.
    public let readyAt: Date
    public let mergedAt: Date
    /// First review by another person after it was ready. Nil where nobody
    /// reviewed, or where the only reviews came from bots.
    public let firstReviewAt: Date?
    /// The last approval before the merge -- the point from which it was
    /// only the merge that was outstanding.
    public let lastApprovalAt: Date?

    public init(
        isBot: Bool,
        readyAt: Date,
        mergedAt: Date,
        firstReviewAt: Date?,
        lastApprovalAt: Date?
    ) {
        self.isBot = isBot
        self.readyAt = readyAt
        self.mergedAt = mergedAt
        self.firstReviewAt = firstReviewAt
        self.lastApprovalAt = lastApprovalAt
    }

    /// Seconds from ready to the first review, or nil if nobody reviewed.
    public var timeToFirstReview: TimeInterval? { interval(from: readyAt, to: firstReviewAt) }
    public var timeToApproval: TimeInterval? { interval(from: readyAt, to: lastApprovalAt) }
    public var approvalToMerge: TimeInterval? { interval(from: lastApprovalAt, to: mergedAt) }
    public var timeToMerge: TimeInterval? { interval(from: readyAt, to: mergedAt) }

    /// Negative intervals are dropped rather than clamped to zero: they mean
    /// the events did not happen in the order assumed, and a zero would be
    /// indistinguishable from an instant review.
    private func interval(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        let seconds = end.timeIntervalSince(start)
        return seconds >= 0 ? seconds : nil
    }
}

/// Periods, medians and the arithmetic behind the trend charts.
public enum TrendMath {
    /// ISO weeks, so a week starts on Monday, in the reader's own time zone.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    /// The periods to chart, oldest first, ending with the one that contains
    /// `reference` -- the current week or month included, still filling.
    public static func periods(
        _ resolution: TrendResolution,
        reference: Date = .now,
        calendar: Calendar = TrendMath.calendar
    ) -> [DateInterval] {
        guard let current = calendar.dateInterval(of: resolution.component, for: reference) else {
            return []
        }

        return (0..<resolution.bucketCount).reversed().compactMap { offset in
            guard
                let start = calendar.date(
                    byAdding: resolution.component,
                    value: -offset,
                    to: current.start
                ),
                let interval = calendar.dateInterval(of: resolution.component, for: start)
            else { return nil }
            return interval
        }
    }

    /// The middle value, or the mean of the two middle ones.
    ///
    /// A median rather than an average: one forgotten pull request with a
    /// month on the clock would drag an average somewhere no pull request
    /// actually was.
    public static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// One period's numbers, for one audience.
    public static func values(merged: [PullRequestTiming], opened: Int) -> TrendValues {
        TrendValues(
            opened: opened,
            merged: merged.count,
            firstReview: point(merged.compactMap(\.timeToFirstReview)),
            approval: point(merged.compactMap(\.timeToApproval)),
            approvalToMerge: point(merged.compactMap(\.approvalToMerge)),
            merge: point(merged.compactMap(\.timeToMerge))
        )
    }

    /// Both audiences from one fetch: the bots are already in hand, so
    /// keeping their numbers costs nothing and makes the toggle instant.
    public static func bucket(
        period: DateInterval,
        merged: [PullRequestTiming],
        openedByPeople: Int,
        openedByEveryone: Int
    ) -> TrendBucket {
        TrendBucket(
            start: period.start,
            end: period.end,
            people: values(merged: merged.filter { !$0.isBot }, opened: openedByPeople),
            everyone: values(merged: merged, opened: openedByEveryone)
        )
    }

    /// One period of one's own pull requests.
    ///
    /// The comment counts go through the same shape as the durations --
    /// fewest, middle, most -- because the question is the same one: was the
    /// period even, or did one pull request carry all the discussion.
    public static func myBucket(
        period: DateInterval,
        opened: [MyPullRequestFacts],
        merged: [PullRequestTiming],
        calendar: Calendar = TrendMath.calendar
    ) -> MyTrendBucket {
        var hours: [Int: Int] = [:]
        for item in opened {
            hours[calendar.component(.hour, from: item.createdAt), default: 0] += 1
        }

        func commenters(_ keyPath: KeyPath<MyPullRequestFacts, [String: Int]>) -> [String: Int] {
            opened.reduce(into: [String: Int]()) { total, item in
                for (login, count) in item[keyPath: keyPath] { total[login, default: 0] += count }
            }
        }

        return MyTrendBucket(
            start: period.start,
            end: period.end,
            opened: opened.count,
            hours: hours,
            commentsFromPeople: point(opened.map { Double($0.commentsFromPeople) }),
            commentsFromEveryone: point(opened.map { Double($0.commentsFromEveryone) }),
            commentersFromPeople: commenters(\.commentersFromPeople),
            commentersFromEveryone: commenters(\.commentersFromEveryone),
            merge: point(merged.compactMap(\.timeToMerge))
        )
    }

    private static func point(_ values: [TimeInterval]) -> TrendPoint {
        TrendPoint(
            median: median(values),
            fastest: values.min(),
            slowest: values.max(),
            samples: values.count
        )
    }

    // MARK: - Formatting

    /// The unit a whole series is drawn in.
    ///
    /// Chosen per chart rather than globally: first reviews land in hours,
    /// merges in days, and one scale for both would flatten three of the
    /// four curves into the axis.
    public enum DurationUnit: String, Sendable {
        case minutes
        case hours
        case days

        public var seconds: TimeInterval {
            switch self {
            case .minutes: 60
            case .hours: 3600
            case .days: 86_400
            }
        }

        public var axisLabel: String {
            switch self {
            case .minutes: "minutes"
            case .hours: "hours"
            case .days: "days"
            }
        }
    }

    /// Picks the unit from the largest value in the series, so the axis is
    /// readable at both ends.
    public static func unit(for values: [TimeInterval]) -> DurationUnit {
        guard let largest = values.max() else { return .hours }
        if largest >= 2 * 86_400 { return .days }
        if largest >= 2 * 3600 { return .hours }
        return .minutes
    }

    /// A duration as a person would say it: "3h 20m", "2.4 days".
    public static func describe(_ seconds: TimeInterval) -> String {
        if seconds < 90 {
            return "\(Int(seconds.rounded()))s"
        }
        if seconds < 3600 {
            return "\(Int((seconds / 60).rounded()))m"
        }
        if seconds < 2 * 86_400 {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds - Double(hours) * 3600) / 60)
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        return String(format: "%.1f days", seconds / 86_400)
    }
}
