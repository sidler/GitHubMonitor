import Foundation

/// How a review's waiting time reads in a row.
public enum WaitingAge: String, Hashable, Sendable, CaseIterable {
    /// Waiting, but not long enough to say anything about.
    case fresh
    case aging
    case overdue

    /// Nil where nothing is waiting: no request named this person, so there
    /// is no clock and nothing to colour.
    public static func of(
        _ item: PullRequestItem,
        agingDays: Int,
        overdueDays: Int,
        now: Date = .now
    ) -> WaitingAge? {
        guard let waiting = item.waiting(asOf: now) else { return nil }
        let days = waiting / 86_400
        // The louder threshold wins where the two are set the wrong way
        // round, rather than the order of these checks deciding it.
        if days >= Double(max(agingDays, overdueDays)) { return .overdue }
        if days >= Double(min(agingDays, overdueDays)) { return .aging }
        return .fresh
    }

    /// What the tooltip says, spelled out.
    public func sentence(days: Int) -> String {
        let span = days == 0 ? "less than a day" : (days == 1 ? "1 day" : "\(days) days")
        switch self {
        case .fresh: return "Your review was asked for \(span) ago"
        case .aging: return "Your review has been waiting \(span)"
        case .overdue: return "Your review has been waiting \(span)"
        }
    }
}
