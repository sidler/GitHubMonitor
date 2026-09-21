import Foundation

/// Parses the ISO 8601 timestamps GitHub returns.
///
/// `nonisolated(unsafe)` is needed here but not for `DateFormatter`:
/// `ISO8601DateFormatter` is not marked `Sendable`. It is safe in practice —
/// the instance is configured once and only ever read afterwards.
enum GitHubDate {
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Falls back to the current time so one unreadable timestamp cannot drop
    /// an otherwise usable item from the list.
    static func date(from value: String?, fallback: Date = .now) -> Date {
        optional(from: value) ?? fallback
    }

    /// For the places where a missing timestamp is an answer rather than a
    /// problem: a pull request that was never merged has no merge date, and
    /// substituting the current time would report it as merged just now.
    static func optional(from value: String?) -> Date? {
        guard let value else { return nil }
        return formatter.date(from: value)
    }
}
