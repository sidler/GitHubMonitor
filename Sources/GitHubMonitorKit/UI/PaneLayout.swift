import CoreGraphics

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
