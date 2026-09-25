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

    /// The same locale rule, for tooltips: "3d ago" is enough to scan a list
    /// by, but not enough to tell two rows of the same day apart.
    static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()

    public static func absolute(_ date: Date) -> String {
        absoluteFormatter.string(from: date)
    }

    /// Wall clock only, for something that happens within the hour.
    static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }
}
