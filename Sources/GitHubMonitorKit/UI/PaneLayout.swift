import SwiftUI

/// The measurements the side panes are built on.
///
/// One place for them because the panes are read as one thing. The pull
/// request pane, the strip beside a diff, the issue pane, a notification
/// and the workload tables all stack headings over content, and each had
/// picked its own gap -- six, eight, ten, twelve, and in one case the
/// whole sixteen that separates one section from the next. A heading that
/// sits as far from its own content as it does from the next section's
/// does not belong to anything, and a pane of them reads as a list of
/// words with things underneath.
enum PaneLayout {
    /// Between a heading and what it introduces.
    ///
    /// Small enough that the two are plainly one group, and the figure
    /// that matters is not this one on its own but its distance from
    /// `betweenSections`: grouping is made of the difference.
    static let headingGap: CGFloat = 5

    /// Between one section and the next.
    static let betweenSections: CGFloat = 16
}

/// Whether the row being drawn is one the list has selected.
///
/// The list paints its own selection now, and a focused one is the
/// system's accent fill. Every colour a row carries deliberately --
/// green for passing, red for a conflict, orange for a wait -- measures
/// between 1.2 and 1.4 to one against that blue, where four and a half is
/// the bar. So on the selected row the colours stand down and let it be
/// white throughout; the rows around it keep them, which is where they
/// are being read anyway, and what the selected one is about is spelled
/// out in the pane beside it.
private struct RowSelectionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var rowIsSelected: Bool {
        get { self[RowSelectionKey.self] }
        set { self[RowSelectionKey.self] = newValue }
    }
}

/// A colour that means something, or nothing where saying it would make
/// the row unreadable.
///
/// Nil and "selected" both come back as the hierarchical style, which the
/// list resolves against whatever it has painted -- white on the accent
/// fill, the ordinary grey off it.
@MainActor
func rowTint(_ color: Color?, selected: Bool) -> AnyShapeStyle {
    guard let color, !selected else { return AnyShapeStyle(.secondary) }
    return AnyShapeStyle(color)
}
