import Foundation

/// Turns `@today-1w` into the date GitHub's search actually accepts.
///
/// The web interface understands relative dates; the search API does not.
/// It answers `"@today-1w" is not a recognized date/time format. Please
/// provide an ISO 8601 date/time value, such as YYYY-MM-DD.` -- and treats
/// it exactly as it treats a word like `banana`. So a query written the way
/// the browser accepts it comes back rejected, which is a poor reason for a
/// list not to work.
///
/// The browser resolves these before searching. So does this, at the moment
/// the search is sent rather than when it is saved: a list written as
/// "closed in the last week" should still mean that next month.
public enum RelativeDates {
    /// How far to move, and in what.
    enum Unit: String {
        case day = "d"
        case week = "w"
        case month = "m"
        case year = "y"

        var component: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    /// `@today`, optionally followed by a signed offset: `@today-1w`,
    /// `@today+3d`, `@today-6m`.
    ///
    /// Anchored on `@today` with no word character before it, so an address
    /// or a branch name that happens to end in "today" is left alone.
    private static let pattern = try? NSRegularExpression(
        pattern: #"(?<!\w)@today(?:([+-])(\d+)([dwmy]))?"#,
        options: [.caseInsensitive]
    )

    /// Every relative date in the text, written out.
    ///
    /// `now` and `calendar` are arguments so the tests can stand somewhere
    /// fixed. The calendar is the local one: what somebody means by "today"
    /// is today where they are, which is also what the browser resolves it
    /// to.
    public static func expand(
        _ query: String, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        guard let pattern else { return query }
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        let matches = pattern.matches(in: query, range: range)
        guard !matches.isEmpty else { return query }

        var result = query
        // Backwards, so replacing one does not move the next one's range.
        for match in matches.reversed() {
            guard
                let whole = Range(match.range, in: query),
                let date = date(for: match, in: query, now: now, calendar: calendar)
            else { continue }
            result.replaceSubrange(whole, with: iso(date, calendar: calendar))
        }
        return result
    }

    /// Whether the text holds anything this would rewrite, for a settings
    /// field that wants to say so.
    public static func mentionsRelativeDate(_ query: String) -> Bool {
        expand(query) != query
    }

    private static func date(
        for match: NSTextCheckingResult, in query: String, now: Date, calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        // A bare `@today` carries no offset.
        guard
            let signRange = Range(match.range(at: 1), in: query),
            let amountRange = Range(match.range(at: 2), in: query),
            let unitRange = Range(match.range(at: 3), in: query),
            let amount = Int(query[amountRange]),
            let unit = Unit(rawValue: query[unitRange].lowercased())
        else { return today }

        let signed = query[signRange] == "-" ? -amount : amount
        return calendar.date(byAdding: unit.component, value: signed, to: today) ?? today
    }

    /// The format GitHub asks for, in the same calendar the arithmetic was
    /// done in -- formatting a local date in UTC would hand back yesterday
    /// for anybody east of Greenwich in the evening.
    static func iso(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }
}
