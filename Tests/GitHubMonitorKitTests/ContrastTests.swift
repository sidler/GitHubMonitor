import AppKit
import SwiftUI
import Testing
@testable import GitHubMonitorKit

/// Whether what the app draws can be read on what it draws it on.
///
/// Measured rather than eyeballed, and in both themes, because half of
/// these were wrong and none of it was obvious: a green tick came in at
/// 2.2 to one on a white list, a yellow one at 1.5, and the name on an
/// issue type at 1.4 against the wash of its own colour.
///
/// Four and a half to one throughout. WCAG asks only three of a symbol,
/// but these colours are shared between symbols and the text beside them,
/// and one bar is one thing to keep.
///
/// Every colour is measured against every ground, including pairs the app
/// does not draw today -- code on a selected row, a label on a diff band.
/// That is deliberate: it costs nothing while they all pass, and it means
/// moving a colour to a new place cannot quietly make it unreadable.
@Suite("What is drawn can be read")
struct ContrastTests {
    private let readable = 4.5

    // MARK: - Measuring

    private func components(
        _ color: Color, _ appearance: NSAppearance, over page: Shade? = nil
    ) -> Shade {
        var out = Shade(0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
            let under = page ?? {
                let paper = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .white
                return Shade(
                    Double(paper.redComponent),
                    Double(paper.greenComponent),
                    Double(paper.blueComponent)
                )
            }()
            // A colour with alpha is only ever seen over something.
            let alpha = Double(resolved.alphaComponent)
            out = Shade(
                Double(resolved.redComponent) * alpha + under.red * (1 - alpha),
                Double(resolved.greenComponent) * alpha + under.green * (1 - alpha),
                Double(resolved.blueComponent) * alpha + under.blue * (1 - alpha)
            )
        }
        return out
    }

    private struct Shade {
        let red: Double, green: Double, blue: Double
        init(_ red: Double, _ green: Double, _ blue: Double) {
            (self.red, self.green, self.blue) = (red, green, blue)
        }

        var luminance: Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }
    }

    private func ratio(_ ink: Shade, _ ground: Shade) -> Double {
        let one = ink.luminance, other = ground.luminance
        return (max(one, other) + 0.05) / (min(one, other) + 0.05)
    }

    // MARK: - What is drawn where

    /// Every colour a row or a diff is painted in.
    private func inks() -> [(String, Color)] {
        var result: [(String, Color)] = [
            ("rowDetail", .rowDetail),
            ("waiting.aging", WaitingAge.aging.tint),
            ("waiting.overdue", WaitingAge.overdue.tint),
            ("merge.conflicting", MergeStatus.conflicting.tint),
            ("merge.mergeable", MergeStatus.mergeable.tint),
        ]
        for decision in ReviewDecision.allCases {
            result.append(("review.\(decision)", decision.tint))
        }
        for status in ChecksStatus.allCases {
            result.append(("checks.\(status)", status.tint))
        }
        for state in ReviewState.allCases {
            result.append(("reviewer.\(state)", state.tint))
        }
        for kind in ReviewTallyKind.allCases {
            result.append(("tally.\(kind.rawValue)", kind.tint))
        }
        for state: LinkedSummary.State in [.open, .draft, .merged, .closed, .notPlanned] {
            result.append(("link.\(state)", state.tint))
        }
        for kind in CodeToken.Kind.allCases {
            result.append(("code.\(kind.rawValue)", kind.tint))
        }
        for type in IssueTypeColor.allCases {
            result.append(("type.\(type.rawValue)", type.tint))
        }
        return result
    }

    /// Every ground one of them lands on.
    private func grounds(_ appearance: NSAppearance) -> [(String, Shade)] {
        let page = components(Color(nsColor: .textBackgroundColor), appearance)
        return [
            ("the page", page),
            (
                "a selected row",
                components(
                    Color(nsColor: .unemphasizedSelectedContentBackgroundColor), appearance
                )
            ),
            ("an added line", components(Color.green.opacity(0.14), appearance, over: page)),
            ("a removed line", components(Color.red.opacity(0.14), appearance, over: page)),
        ]
    }

    // MARK: - The checks

    @Test("Every colour clears 4.5 to one on every ground", arguments: [false, true])
    func everywhere(inDarkMode: Bool) {
        let appearance = NSAppearance(named: inDarkMode ? .darkAqua : .aqua)!
        for (name, ink) in inks() {
            let shade = components(ink, appearance)
            for (where_, ground) in grounds(appearance) {
                let measured = ratio(shade, ground)
                #expect(measured >= readable, "\(name) on \(where_) is \(measured) to one")
            }
        }
    }

    /// A chip lays a wash of its own hue down and writes on it. The two
    /// used to be the same colour at two strengths, which read at 1.4 to
    /// one for a yellow type -- the wash comes from the system hue now and
    /// the name from the weighted one.
    @Test("An issue type can be read on its own chip", arguments: [false, true])
    func typeChips(inDarkMode: Bool) {
        let appearance = NSAppearance(named: inDarkMode ? .darkAqua : .aqua)!
        for type in IssueTypeColor.allCases {
            for (where_, ground) in grounds(appearance) where !where_.hasSuffix("line") {
                let chip = components(Ink.wash(type.system), appearance, over: ground)
                let measured = ratio(components(type.tint, appearance), chip)
                #expect(
                    measured >= readable,
                    "\(type.rawValue) on its chip over \(where_) is \(measured) to one"
                )
            }
        }
    }

    /// A label's colour comes from GitHub and cannot be moved, so the app
    /// picks the text to go on it. These are the colours GitHub's own
    /// defaults use, plus the two extremes.
    @Test("A label's name can be read on whatever colour GitHub gave it")
    func labelChips() {
        let colours = [
            "d73a4a", "0e8a16", "fbca04", "0075ca", "7057ff", "c5def5",
            "e4e669", "cfd3d7", "ffffff", "000000", "008672", "d4c5f9",
        ]
        for value in colours {
            let label = IssueLabel(name: value, color: value)
            guard let parts = label.components else {
                Issue.record("\(value) did not parse")
                continue
            }
            let ground = Shade(parts.red, parts.green, parts.blue)
            let ink = label.prefersDarkText ? Shade(0.1, 0.1, 0.1) : Shade(1, 1, 1)
            let measured = ratio(ink, ground)
            #expect(measured >= readable, "#\(value) reads at \(measured) to one")
        }
    }

    /// The hues are the system's; only the weight has moved. A colour that
    /// had drifted would be a different answer to "which of these is a
    /// warning".
    @Test("The hues are still the ones the system uses")
    func hues() {
        let appearance = NSAppearance(named: .aqua)!
        let pairs: [(String, Color, Color)] = [
            ("red", Ink.red, .red), ("orange", Ink.orange, .orange),
            ("yellow", Ink.yellow, .yellow), ("green", Ink.green, .green),
            ("teal", Ink.teal, .teal), ("blue", Ink.blue, .blue),
            ("indigo", Ink.indigo, .indigo), ("purple", Ink.purple, .purple),
            ("pink", Ink.pink, .pink),
        ]

        for (name, ours, theirs) in pairs {
            #expect(apart(ours, theirs, appearance) < 0.05, "\(name) moved around the wheel")
        }
    }

    private func apart(_ one: Color, _ other: Color, _ appearance: NSAppearance) -> CGFloat {
        var first: CGFloat = 0, second: CGFloat = 0
        var saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            (NSColor(one).usingColorSpace(.sRGB) ?? .black).getHue(
                &first, saturation: &saturation, brightness: &brightness, alpha: &alpha
            )
            (NSColor(other).usingColorSpace(.sRGB) ?? .black).getHue(
                &second, saturation: &saturation, brightness: &brightness, alpha: &alpha
            )
        }
        return min(abs(first - second), 1 - abs(first - second))
    }
}
