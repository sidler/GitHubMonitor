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
        guard let value, let date = formatter.date(from: value) else { return fallback }
        return date
    }
}
