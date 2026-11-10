import Foundation

/// One review somebody submitted.
public struct SubmittedReview: Hashable, Sendable {
    public let reviewer: String
    public let at: Date

    public init(reviewer: String, at: Date) {
        self.reviewer = reviewer
        self.at = at
    }
}

/// One time somebody was asked to review.
public struct RequestedReview: Hashable, Sendable {
    public let reviewer: String
    public let at: Date

    public init(reviewer: String, at: Date) {
        self.reviewer = reviewer
        self.at = at
    }
}

/// A pull request as the reviewer figures need it: who was asked, when,
/// who answered, when, and whether it is still open.
public struct ReviewedPullRequest: Hashable, Sendable, Identifiable {
    public var id: String { key }
    /// Something unique per pull request, for counting distinct ones.
    public let key: String
    /// Nil while it is still open, which is what makes an unanswered
    /// request pending rather than ignored.
    public let closedAt: Date?
    /// Who opened it. Nil where GitHub has forgotten the account.
    ///
    /// Kept because a remark somebody leaves on their own pull request
    /// is not code they read: GitHub files it as a review all the same,
    /// and counting it would have people reviewing themselves to the top
    /// of the ranking.
    public let author: String?
    public let requests: [RequestedReview]
    public let reviews: [SubmittedReview]
    /// Who was still on the list of requested reviewers when this was
    /// last looked at -- at the close, for one that is closed.
    ///
    /// The history of requests is not the same thing. Somebody asked and
    /// then unasked, or asked and then superseded by a re-request after
    /// they had already answered, left a request event behind that nobody
    /// was ever waiting on. Counting those as ignored put colleagues at
    /// a quarter when the truth was a twentieth.
    public let stillRequested: Set<String>

    public var isOpen: Bool { closedAt == nil }

    public init(
        key: String,
        closedAt: Date?,
        author: String? = nil,
        requests: [RequestedReview],
        reviews: [SubmittedReview],
        stillRequested: Set<String> = []
    ) {
        self.key = key
        self.closedAt = closedAt
        self.author = author
        self.requests = requests
        self.reviews = reviews
        self.stillRequested = stillRequested
    }
}

/// What one reviewer did, over whatever stretch was read.
///
/// Two halves, because they answer different questions and are not
/// comparable. The counts say how much of the reviewing somebody does;
/// the durations say how long the rest of the team waits on them. A
/// person can be first on both lists or on neither.
public struct ReviewerStats: Hashable, Sendable, Identifiable {
    public var id: String { reviewer }
    public let reviewer: String

    // MARK: How much

    /// Pull requests this person reviewed at least once.
    ///
    /// Distinct, because three rounds of comments on one pull request is
    /// one pull request read -- counting it as three would flatter
    /// whoever argues the most.
    public let pullRequests: Int
    /// Every review submitted, comment rounds included.
    public let reviews: Int

    // MARK: How long

    /// Seconds from being asked to answering, for the requests that were
    /// answered. Nil where none were.
    public let median: TimeInterval?
    public let mean: TimeInterval?
    /// The slow tail: nine answers in ten came faster than this.
    ///
    /// Beside the median rather than instead of it. A median of two hours
    /// with a ninetieth percentile of four days is a different person
    /// from a median of two hours with a ninetieth of three.
    public let p90: TimeInterval?
    /// How many requests were answered, which is what the durations are
    /// measured over.
    public let answered: Int
    /// Asked, never answered, and still asked when the pull request
    /// closed. Not a slow answer -- no answer.
    ///
    /// Still asked at the close, rather than every request that went
    /// unanswered: a request withdrawn is not a question anybody was
    /// left waiting on.
    public let ignored: Int
    /// Requests still outstanding on pull requests that are still open.
    /// The clock on these has not stopped.
    public let pending: Int

    /// The share of settled requests this person never answered.
    ///
    /// Out of the settled ones only: a request still open is not yet
    /// either kept or ignored, and counting it would make somebody look
    /// worse the busier the repository is this week.
    public var ignoredShare: Double? {
        let settled = answered + ignored
        guard settled > 0 else { return nil }
        return Double(ignored) / Double(settled)
    }

    /// Which of the three steps the bar is coloured in.
    ///
    /// Here rather than in the view so the legend and the bars cannot drift
    /// apart: a legend printed in different colours from the rows it
    /// explains is worse than no legend at all.
    public var band: IgnoredBand {
        guard let share = ignoredShare else { return .few }
        if share >= IgnoredBand.many.floor { return .many }
        if share >= IgnoredBand.some.floor { return .some }
        return .few
    }

    public init(
        reviewer: String,
        pullRequests: Int,
        reviews: Int,
        median: TimeInterval?,
        mean: TimeInterval?,
        p90: TimeInterval?,
        answered: Int,
        ignored: Int,
        pending: Int
    ) {
        self.reviewer = reviewer
        self.pullRequests = pullRequests
        self.reviews = reviews
        self.median = median
        self.mean = mean
        self.p90 = p90
        self.answered = answered
        self.ignored = ignored
        self.pending = pending
    }
}

/// How much of what somebody was asked for went unanswered, in the three
/// steps the speed table colours its bars by.
///
/// Three rather than a gradient: the question a reader has is "is this one
/// worth a word", and a colour that slides continuously answers it with a
/// shade nobody can name.
public enum IgnoredBand: String, CaseIterable, Sendable {
    /// Under a tenth of the settled requests went unanswered.
    case few
    /// A tenth up to a quarter.
    case some
    /// A quarter or more.
    case many

    /// The share at which this step begins.
    public var floor: Double {
        switch self {
        case .few: 0
        case .some: 0.1
        case .many: 0.25
        }
    }

    /// What the colour says, for the legend.
    ///
    /// Worded about the requests rather than about the person: slow is not
    /// the same failing as absent, and the bar is already saying slow.
    public var label: String {
        switch self {
        case .few: "under a tenth unanswered"
        case .some: "a tenth to a quarter"
        case .many: "a quarter or more"
        }
    }
}

/// Works the reviewer figures out of the pull requests they came from.
public enum ReviewerStatsMath {
    /// Everybody who reviewed or was asked to, with their numbers.
    ///
    /// `since` is the start of the stretch the table is about, and
    /// everything older than it is dropped. It has to be, because the
    /// search these pull requests came from cannot be asked the question
    /// the table asks. There is no qualifier for "reviewed in March", so
    /// the fetch asks for pull requests *touched* in the window and the
    /// window is applied here -- and a pull request opened years ago and
    /// touched last week brings its whole reviewing history with it.
    /// Left unfiltered, a repository's twelve-month table listed people
    /// who had not reviewed anything in five years, and a sixth of every
    /// count on it was older than the window it was labelled with.
    ///
    /// Anchored on when each thing happened, which for a wait means when
    /// it was *asked* rather than when it was answered. A request made
    /// inside the window can only be answered inside it -- the window
    /// ends now -- so nothing is lost at that end, while anchoring on the
    /// answer would let a request from three years ago put a three-year
    /// wait into this year's median.
    public static func summarise(
        _ pullRequests: [ReviewedPullRequest],
        since: Date
    ) -> [ReviewerStats] {
        var reviews: [String: Int] = [:]
        var touched: [String: Set<String>] = [:]
        var waits: [String: [TimeInterval]] = [:]
        var ignored: [String: Int] = [:]
        var pending: [String: Int] = [:]

        for pullRequest in pullRequests {
            for review in pullRequest.reviews where review.at >= since {
                // Not your own. GitHub lets you leave a review on a pull
                // request you opened, and it is not code you read.
                guard review.reviewer != pullRequest.author else { continue }
                reviews[review.reviewer, default: 0] += 1
                touched[review.reviewer, default: []].insert(pullRequest.key)
            }
            for (reviewer, answer) in answers(in: pullRequest, since: since) {
                switch answer {
                case .after(let wait):
                    waits[reviewer, default: []].append(wait)
                case .never:
                    // Only where they are still on the list. A request
                    // that was withdrawn, or one left behind by a
                    // re-request after they had answered, is not an
                    // unanswered question -- nobody was waiting on it.
                    guard pullRequest.stillRequested.contains(reviewer) else { continue }
                    if pullRequest.isOpen {
                        pending[reviewer, default: 0] += 1
                    } else {
                        ignored[reviewer, default: 0] += 1
                    }
                }
            }
        }

        let everybody = Set(reviews.keys)
            .union(waits.keys).union(ignored.keys).union(pending.keys)

        return everybody.map { reviewer in
            let answered = waits[reviewer] ?? []
            return ReviewerStats(
                reviewer: reviewer,
                pullRequests: touched[reviewer]?.count ?? 0,
                reviews: reviews[reviewer] ?? 0,
                median: TrendMath.median(answered),
                mean: answered.isEmpty
                    ? nil : answered.reduce(0, +) / Double(answered.count),
                p90: percentile(answered, 0.9),
                answered: answered.count,
                ignored: ignored[reviewer] ?? 0,
                pending: pending[reviewer] ?? 0
            )
        }
    }

    private enum Answer {
        case after(TimeInterval)
        case never
    }

    /// What became of each request on one pull request.
    ///
    /// Request by request rather than once per person, because being asked
    /// again after a round of changes is a second wait that the team feels
    /// as keenly as the first. Each review answers at most one request --
    /// the earliest it could have answered -- so a reviewer who answers
    /// twice has answered two requests and not the same one twice.
    private static func answers(
        in pullRequest: ReviewedPullRequest,
        since: Date
    ) -> [(String, Answer)] {
        var result: [(String, Answer)] = []
        let requests = pullRequest.requests.filter { $0.at >= since }
        let askedOf = Set(requests.map(\.reviewer))

        for reviewer in askedOf {
            let asked = requests
                .filter { $0.reviewer == reviewer }
                .map(\.at)
                .sorted()
            // The answers are not cut to the window: one of them is only
            // ever used to settle a request that is, and a request inside
            // the window has no answer before it.
            var answers = pullRequest.reviews
                .filter { $0.reviewer == reviewer }
                .map(\.at)
                .sorted()

            for request in asked {
                guard let index = answers.firstIndex(where: { $0 >= request }) else {
                    result.append((reviewer, .never))
                    continue
                }
                result.append((reviewer, .after(answers[index].timeIntervalSince(request))))
                answers.remove(at: index)
            }
        }
        return result
    }

    /// The value below which that share of the answers fall.
    ///
    /// Nearest rank, which is what a reader of a table expects: the
    /// ninetieth percentile of ten answers is the ninth of them, a number
    /// somebody actually waited, not an interpolation between two.
    public static func percentile(_ values: [TimeInterval], _ share: Double) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((share * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    /// Busiest first, for the table that asks who does the reviewing.
    public static func byVolume(_ stats: [ReviewerStats]) -> [ReviewerStats] {
        stats.sorted { lhs, rhs in
            if lhs.pullRequests != rhs.pullRequests {
                return lhs.pullRequests > rhs.pullRequests
            }
            if lhs.reviews != rhs.reviews { return lhs.reviews > rhs.reviews }
            return lhs.reviewer.localizedStandardCompare(rhs.reviewer) == .orderedAscending
        }
    }

    /// Slowest first, and only those with an answer to measure.
    ///
    /// Somebody who has never answered a request has no time to rank, and
    /// putting them at either end of a list about speed would say
    /// something the data does not.
    public static func bySpeed(_ stats: [ReviewerStats]) -> [ReviewerStats] {
        stats
            .filter { $0.median != nil }
            .sorted { lhs, rhs in
                let left = lhs.median ?? 0
                let right = rhs.median ?? 0
                if left != right { return left > right }
                return lhs.reviewer.localizedStandardCompare(rhs.reviewer) == .orderedAscending
            }
    }
}
