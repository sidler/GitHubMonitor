import AppKit
import SwiftUI
import Testing

@testable import GitHubMonitorKit

/// The pair of symbols in a diff's toolbar, and what rests under the
/// pointer on each of them.
@Suite("Symbol choice")
@MainActor
struct SymbolChoiceTests {
    /// Hosts the view far enough to get at the control it makes.
    private func control<Tag: Hashable>(of view: SymbolChoice<Tag>) -> NSSegmentedControl? {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        host.layoutSubtreeIfNeeded()
        return found(in: host)
    }

    private func found(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl { return control }
        for sub in view.subviews {
            if let control = found(in: sub) { return control }
        }
        return nil
    }

    /// The reason this control is drawn by hand rather than with a
    /// `Picker`: a picker's segments come out with no tooltip, so the two
    /// symbols can only share one, and sharing one is exactly what left
    /// nobody able to tell them apart.
    @Test("Every segment says what it does on its own")
    func tooltips() throws {
        let control = try #require(
            control(
                of: SymbolChoice(
                    options: DiffPaging.allCases.map {
                        .init(tag: $0, symbolName: $0.symbolName, label: $0.label, tip: $0.tip)
                    },
                    selection: .scroll,
                    choose: { _ in }
                )
            )
        )

        #expect(control.segmentCount == 2)
        #expect(control.toolTip(forSegment: 0) == DiffPaging.scroll.tip)
        #expect(control.toolTip(forSegment: 1) == DiffPaging.oneFile.tip)
        #expect(control.selectedSegment == 0)
    }

    @Test("The layout pair says which column count is which")
    func layoutTooltips() throws {
        let control = try #require(
            control(
                of: SymbolChoice(
                    options: DiffLayout.allCases.map {
                        .init(tag: $0, symbolName: $0.symbolName, label: $0.label, tip: $0.tip)
                    },
                    selection: .sideBySide,
                    choose: { _ in }
                )
            )
        )

        #expect(control.toolTip(forSegment: 0) == DiffLayout.unified.tip)
        #expect(control.toolTip(forSegment: 1) == DiffLayout.sideBySide.tip)
        #expect(control.selectedSegment == 1)
    }

    /// A symbol with no description is a button a screen reader cannot
    /// name, and these have no visible label to fall back on.
    @Test("Every segment carries a name for VoiceOver")
    func descriptions() throws {
        let control = try #require(
            control(
                of: SymbolChoice(
                    options: DiffPaging.allCases.map {
                        .init(tag: $0, symbolName: $0.symbolName, label: $0.label, tip: $0.tip)
                    },
                    selection: .scroll,
                    choose: { _ in }
                )
            )
        )

        #expect(control.image(forSegment: 0)?.accessibilityDescription == "All files")
        #expect(control.image(forSegment: 1)?.accessibilityDescription == "One file")
    }

    /// The one thing about this control that cannot be seen in a
    /// screenshot: that pressing a segment reaches the app at all.
    @Test("Pressing a segment chooses that mode")
    func pressing() throws {
        let chosen = Chosen()
        let control = try #require(
            control(
                of: SymbolChoice(
                    options: DiffPaging.allCases.map {
                        .init(tag: $0, symbolName: $0.symbolName, label: $0.label, tip: $0.tip)
                    },
                    selection: .scroll,
                    choose: { chosen.value = $0 }
                )
            )
        )

        control.selectedSegment = 1
        let target = try #require(control.target)
        let action = try #require(control.action)
        _ = target.perform(action, with: control)

        #expect(chosen.value == .oneFile)
    }

    @MainActor
    final class Chosen {
        var value: DiffPaging?
    }

    @Test("Each tooltip names its own mode and says what it does")
    func wording() {
        for paging in DiffPaging.allCases {
            #expect(paging.tip.hasPrefix(paging.label))
            #expect(paging.tip.count > paging.label.count + 10)
        }
        for layout in DiffLayout.allCases {
            #expect(layout.tip.lowercased().hasPrefix(layout.label.lowercased()))
        }
    }
}
