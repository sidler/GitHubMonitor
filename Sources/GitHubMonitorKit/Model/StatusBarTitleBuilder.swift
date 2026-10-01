import Foundation

/// How the counts are rendered in the menu bar.
public enum StatusBarStyle: String, CaseIterable, Codable, Sendable {
    /// `⑂ 3  ◉ 5  ◍ 2` -- every count, each with its own symbol.
    case separate
    /// A single number: everything that wants attention.
    case sum
    /// Like `separate`, but a count of zero collapses to just its symbol.
    case hideZero

    public var label: String {
        switch self {
        case .separate: "All counts"
        case .sum: "Single total"
        case .hideZero: "All, hide zeros"
        }
    }
}

/// Overall health of the data behind the counts. Drives whether we show
/// numbers at all -- missing data must not masquerade as a real zero.
public enum StatusBarHealth: Equatable, Sendable {
    case ok
    /// No token configured yet.
    case unconfigured
    /// The last refresh failed, but an earlier one succeeded, so the counts
    /// on hand are real numbers that were true a few minutes ago.
    ///
    /// Drawn exactly like `ok`. A timeout is usually over before anybody
    /// looks, and replacing five counts with a warning triangle for it
    /// throws away everything the menu bar is for to report a condition
    /// that will have passed by the next tick. The failure is not hidden:
    /// it is in the tooltip, and in red at the foot of the window and the
    /// popover, where there is room to say what went wrong and a button to
    /// try again.
    case stale
    /// The last refresh failed and nothing earlier succeeded, so there is
    /// nothing to fall back to. Counting zero here would be a lie about an
    /// empty queue rather than a report of an unanswered question.
    case failing

    /// Whether the last refresh failed, either way.
    public var isFailure: Bool { self == .stale || self == .failing }
}

/// A renderable piece of the menu bar title. Kept symbolic rather than
/// pre-rendered so the layout logic stays unit testable.
public enum StatusBarSegment: Equatable, Sendable {
    case symbol(String)
    case text(String)
}

public enum StatusBarTitleBuilder {
    public static let pullRequestSymbol = "arrow.triangle.pull"
    public static let mentionSymbol = "bell"
    public static let issueSymbol = "smallcircle.filled.circle"
    public static let warningSymbol = "exclamationmark.triangle.fill"
    public static let unconfiguredSymbol = "key.slash"

    /// Shown in place of the counts when every one of them is switched off,
    /// so the icon is still there to click and still says why it is quiet.
    public static let quietSymbol = "eye.slash"

    /// The counts to render, in the order they are read. Whichever lists the
    /// user left switched on for the menu bar; an empty list is a deliberate
    /// choice rather than an error, and is drawn as such.
    public static func segments(
        counts: [SurfaceCount],
        style: StatusBarStyle,
        health: StatusBarHealth
    ) -> [StatusBarSegment] {
        switch health {
        case .unconfigured:
            return [.symbol(unconfiguredSymbol)]
        case .failing:
            return [.symbol(warningSymbol)]
        case .ok, .stale:
            break
        }

        guard !counts.isEmpty else { return [.symbol(quietSymbol)] }

        switch style {
        case .sum:
            let total = counts.reduce(0) { $0 + $1.count }
            // The first symbol still on show leads the total, so the icon
            // keeps saying what is being counted.
            return [.symbol(counts[0].symbolName), .text(" \(total)")]

        case .separate:
            return counts.enumerated().flatMap { index, entry -> [StatusBarSegment] in
                // Two spaces between groups, none after the last.
                let gap = index == counts.count - 1 ? "" : "  "
                return [.symbol(entry.symbolName), .text(" \(entry.count)\(gap)")]
            }

        case .hideZero:
            // A zero says nothing its symbol does not already say, and
            // several counts in a menu bar are worth keeping narrow.
            return counts.enumerated().flatMap { index, entry -> [StatusBarSegment] in
                var segments: [StatusBarSegment] = [.symbol(entry.symbolName)]
                if entry.count > 0 {
                    segments.append(.text(" \(entry.count)"))
                }
                if index < counts.count - 1 {
                    segments.append(.text("  "))
                }
                return segments
            }
        }
    }

    /// Plain-text rendering used for accessibility labels and tests.
    public static func accessibilityLabel(
        counts: [SurfaceCount],
        health: StatusBarHealth
    ) -> String {
        switch health {
        case .unconfigured: return "GitHub Monitor: no token configured"
        case .failing: return "GitHub Monitor: last refresh failed"
        case .ok, .stale: break
        }

        // Where the numbers are old, the tooltip is where that is said. It
        // costs nothing until somebody asks, which is the right price for a
        // condition that is usually over before they do.
        let suffix = health == .stale ? " \u{2014} last refresh failed" : ""

        guard !counts.isEmpty else {
            return "GitHub Monitor: no counts shown in the menu bar" + suffix
        }
        let phrases = counts.map { "\($0.count) \($0.title.lowercased())" }
        return "GitHub Monitor: " + phrases.joined(separator: ", ") + suffix
    }
}
