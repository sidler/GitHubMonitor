import Foundation

/// Relative timestamps for the UI.
///
/// Deliberately pinned to English rather than the system locale: the rest of
/// the interface is English, and a German "vor 3 Tagen" next to "Reviews
/// requested" reads as a bug.
@MainActor
public enum RelativeTime {
    /// Below this, "just now" is both friendlier and more honest than
    /// `RelativeDateTimeFormatter`, which renders a fresh timestamp as the
    /// nonsensical "in 0 seconds".
    static let justNowThreshold: TimeInterval = 60

    static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    public static func string(for date: Date, relativeTo reference: Date = .now) -> String {
        if abs(date.timeIntervalSince(reference)) < justNowThreshold {
            return "just now"
        }
        return formatter.localizedString(for: date, relativeTo: reference)
    }
}
