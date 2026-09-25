import Foundation

/// One review answered: when it was asked of you, and when you answered.
public struct ReviewResponse: Hashable, Sendable {
    public let requestedAt: Date
    public let respondedAt: Date

    public init(requestedAt: Date, respondedAt: Date) {
        self.requestedAt = requestedAt
        self.respondedAt = respondedAt
    }

    public var duration: TimeInterval { respondedAt.timeIntervalSince(requestedAt) }

    /// The one round worth measuring on a pull request: the first time the
    /// review was asked of this person, and the first review they left after
    /// it.
    ///
    /// The first round rather than every round, so a pull request weighs the
    /// same however many times it went back and forth -- and because later
    /// rounds are quick by nature, which would flatter the number.
    ///
    /// Nil where nothing was asked of them by name, or where they never
    /// answered: an unanswered request has no duration, and counting it as
    /// one would make the figure depend on when someone happened to look.
    public static func firstRound(
        requests: [Date], reviews: [Date]
    ) -> ReviewResponse? {
        guard let requested = requests.min() else { return nil }
        guard let responded = reviews.filter({ $0 >= requested }).min() else { return nil }
        return ReviewResponse(requestedAt: requested, respondedAt: responded)
    }
}
