import SwiftUI
import Testing

@testable import GitHubMonitorKit

/// What a row does with its colours when the list has selected it.
///
/// The list paints its own selection now, and a focused one is the
/// system's accent fill. Measured against that blue, every colour a row
/// carries deliberately came out between 1.2 and 1.4 to one where the bar
/// is four and a half: the green tick, the red conflict, the orange wait.
/// So on the selected row they stand down and it is drawn in the
/// hierarchical style, which the system resolves against whatever it has
/// painted. The rows around it keep their colours, which is where they
/// are being read anyway.
@MainActor
@Suite("A row's colours while it is selected")
struct RowTintTests {
    /// `AnyShapeStyle` cannot be compared, so the two outcomes are told
    /// apart by what they describe themselves as. Crude, and it is the
    /// only handle there is on a type that hides its contents.
    private func isHierarchical(_ style: AnyShapeStyle) -> Bool {
        !String(describing: style).contains("Color")
    }

    @Test("Off the selection a colour is drawn as itself")
    func unselected() {
        #expect(!isHierarchical(rowTint(Ink.green, selected: false)))
        #expect(!isHierarchical(rowTint(Ink.red, selected: false)))
    }

    /// The rule this exists for.
    @Test("On the selection every colour stands down")
    func selected() {
        for colour in [Ink.green, Ink.red, Ink.orange, Ink.purple, Ink.gray] {
            #expect(isHierarchical(rowTint(colour, selected: true)))
        }
    }

    /// No colour means the row's own quiet style either way, which is
    /// what lets the list turn it white along with everything else.
    @Test("Having nothing to say is the quiet style, selected or not")
    func noColour() {
        #expect(isHierarchical(rowTint(nil, selected: false)))
        #expect(isHierarchical(rowTint(nil, selected: true)))
    }

    /// Which colour text takes on a selected row, and why it is two.
    ///
    /// Only the key window draws the accent fill. Any other state draws a
    /// quiet grey, where white would be as unreadable as the navy that
    /// started all of this was on blue -- so the two cases must not
    /// collapse into one.
    @Test("Text on a selection follows whether the window has the keyboard")
    func ink() {
        #expect(selectedRowInk(keyWindow: true) != selectedRowInk(keyWindow: false))
        #expect(
            selectedRowInk(keyWindow: true)
                == Color(nsColor: .alternateSelectedControlTextColor)
        )
        #expect(
            selectedRowInk(keyWindow: false) == Color(nsColor: .selectedControlTextColor)
        )
    }

    /// A wait with nothing to report wears no colour of its own, which is
    /// what the timestamp relies on to follow the row.
    @Test("A fresh wait is not a colour")
    func freshWait() {
        #expect(WaitingAge.fresh.tint == nil)
        #expect(WaitingAge.aging.tint != nil)
        #expect(WaitingAge.overdue.tint != nil)
    }
}
