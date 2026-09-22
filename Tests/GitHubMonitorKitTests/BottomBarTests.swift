import AppKit
import SwiftUI
import Testing
@testable import GitHubMonitorKit

/// The bars along the bottom of the window's columns sit side by side and
/// are read as one strip, so a point of difference between them shows up as
/// a step where the columns meet. These measure the real views rather than
/// trusting that two sets of paddings still agree.
@MainActor
@Suite("Bottom bars")
struct BottomBarTests {
    private func height(_ view: some View, width: CGFloat = 420) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("The status bar and the detail pane's actions are the same height")
    func barsAgree() {
        let status = height(
            BottomBar {
                HStack {
                    Label("31", systemImage: "arrow.triangle.pull")
                    Spacer()
                    Text("Updated just now")
                }
            }
        )
        let actions = height(
            BottomBar {
                HStack {
                    Button("Open on GitHub") {}
                    Spacer()
                    Button("Mark as read") {}
                }
                .buttonStyle(.accessoryBar)
            }
        )
        #expect(status == actions, "status \(status) actions \(actions)")
    }

    /// The sidebar's settings button sits on the same bottom edge as the
    /// other two bars, so it has to be the same height as them.
    @Test("The sidebar's settings bar lines up with the rest")
    func sidebarBarAgrees() {
        let status = height(BottomBar { Text("31") })
        let settings = height(
            BottomBar {
                Button {} label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.accessoryBar)
            },
            width: 220
        )
        #expect(status == settings, "status \(status) settings \(settings)")
    }

    /// What one column puts in its bar must not move the other column's
    /// edge, so the height cannot depend on the contents.
    @Test("An empty bar is as tall as a full one")
    func contentDoesNotChangeTheHeight() {
        // Not EmptyView: it produces no view at all, so the bar's own
        // frame would have nothing to apply to and the test would pass on a
        // technicality.
        let empty = height(BottomBar { Color.clear.frame(width: 1, height: 1) })
        let full = height(
            BottomBar {
                HStack {
                    Text("31")
                    LegendBar(symbols: everySymbol)
                    Spacer()
                    Text("Updated just now")
                }
            }
        )
        #expect(empty == full, "empty \(empty) full \(full)")
    }

    /// The legend shares its bar with the pane's actions beside it; a second
    /// line would push one column's edge past the other's.
    @Test("The legend stays on one line, however many symbols it explains")
    func legendIsOneLine() {
        let oneSymbol = height(LegendBar(symbols: [.review(.approved)]))
        let allSymbols = height(LegendBar(symbols: everySymbol))
        #expect(oneSymbol == allSymbols, "one \(oneSymbol) all \(allSymbols)")
    }

    private var everySymbol: [LegendSymbol] {
        ReviewDecision.allCases.map(LegendSymbol.review)
            + ChecksStatus.allCases.map(LegendSymbol.checks)
            + ReviewTallyKind.allCases.map(LegendSymbol.reviewers)
            + [.draft, .comments, .milestone]
    }
}
