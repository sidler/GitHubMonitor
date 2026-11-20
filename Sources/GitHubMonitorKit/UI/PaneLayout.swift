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
/// What AppKit draws text in on top of a selected row.
///
/// White while the window has the keyboard, and the ordinary label colour
/// when it does not -- the same distinction the fill itself makes, since
/// only the key window draws the accent and any other state draws a quiet
/// grey where white would be as unreadable as navy is on blue.
@MainActor
func selectedRowInk(keyWindow: Bool) -> Color {
    Color(nsColor: keyWindow ? .alternateSelectedControlTextColor : .selectedControlTextColor)
}

@MainActor
func rowTint(_ color: Color?, selected: Bool) -> AnyShapeStyle {
    guard let color, !selected else { return AnyShapeStyle(.secondary) }
    return AnyShapeStyle(color)
}

/// Where a ticket stands, who is on it, and which board it sits on.
///
/// One view for the two panes that answer the same question about an
/// issue -- its own detail pane, and the fold a pull request shows for a
/// ticket it is linked to. Built once so a fact added to one cannot go
/// missing from the other, which is exactly how the detail pane came to
/// be the only place that said none of this.
///
/// Larger than the line of asides under it, deliberately. These three are
/// what somebody opens a ticket to find out, and at caption grey they
/// read as footnotes to the title rather than as the answer.
struct TicketFacts: View {
    let state: LinkedSummary.State
    let assignees: [String]
    let projects: [LinkedProject]
    /// How to move it to another column, and which issue it is. Nil
    /// leaves the board chips a reader, which is what the linked-ticket
    /// fold in a pull request's pane is.
    var board: BoardWriting?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            facts
            if !projects.isEmpty { boards }
        }
    }

    /// Where it stands and who is on it: two chips, one line.
    private var facts: some View {
        FlowRow(spacing: 6) {
            // The state carries its own colour; the other two are drawn
            // on the quiet fill the labels use. All three are chips, and
            // all three the same size: as a line of small grey text the
            // two that were added read as a footnote to the title rather
            // than as the answer somebody opened the pane for.
            chip(
                Text(state.label),
                fill: state.tint,
                ink: AnyShapeStyle(.white),
                weight: .semibold
            )
                .help("This is \(state.label.lowercased())")

            chip(
                Label(assigned, systemImage: "person.crop.circle"),
                ink: assignees.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
            )
            .help(assignees.isEmpty ? "Nobody is assigned" : "Assigned to \(assigned)")

        }
        .lineLimit(1)
    }

    /// The boards, one per line, with the columns lined up under each
    /// other.
    ///
    /// They used to be chips on the line above. A ticket sits on two
    /// boards often enough that the line wrapped anyway -- so they each
    /// had a line already, just not one that lined up: every capsule is
    /// as wide as its own name, which put "In Progress" and "Backlog" at
    /// two different places down the pane. A grid costs the same height
    /// and answers "which column is it in on each" by looking down one
    /// column rather than reading both rows.
    private var boards: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            ForEach(projects, id: \.self) { project in
                GridRow {
                    // The weighted grey, not `.secondary`: that one is
                    // tuned for a line somebody may skip, and a board's
                    // name sat lighter than the badge beside it -- which
                    // put the emphasis on the quiet half of the row. Dark
                    // enough to read, still quieter than the column.
                    Label(project.title, systemImage: "rectangle.split.3x1")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.gray)
                        .lineLimit(1)
                        .help("On the board \(project.title)")

                    column(project)
                }
            }
        }
    }

    /// The column, as a badge, and a way to move it where there is one.
    ///
    /// A menu rather than a picker sheet, for the same reason the labels
    /// use one: a column is set by mistake in one click and unset by the
    /// same click again, so ceremony in front of it would cost more than
    /// it saves. Nobody is notified either way.
    @ViewBuilder
    private func column(_ project: LinkedProject) -> some View {
        let face = badge(project)

        if let board, project.isSettable {
            Menu {
                ForEach(project.statuses) { status in
                    Button {
                        board.controller.setProjectStatus(
                            status, on: board.issueID, in: project
                        )
                    } label: {
                        // A tick on the column it is in, so the menu says
                        // where it stands as well as where it could go.
                        // By id: a board that has been moved shows its new
                        // column before GitHub has answered, and the tick
                        // has to move with it.
                        if status.id == project.statusOptionID {
                            Label(status.name, systemImage: "checkmark")
                        } else {
                            Text(status.name)
                        }
                    }
                }
            } label: {
                face
            }
            // `.button` with a plain button under it, not
            // `.borderlessButton`: that style is an NSPopUpButton
            // underneath and draws its label as text, so the badge's
            // wash was dropped and so, before it, was everything after
            // the first word.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
            .help("Move it to another column of \(project.title)")
            .accessibilityLabel("Column on \(project.title)")
        } else {
            face
        }
    }

    /// The column itself: its name on a wash of the colour the board
    /// paints it in.
    ///
    /// A badge rather than coloured text, which is what the issue type
    /// beside it already is -- and the wash is what makes a column read
    /// as a state rather than as a second half of the board's name. The
    /// wash comes from the system hue and the name from the weighted
    /// one: a badge drawn in one colour at two strengths is a badge
    /// nobody can read.
    ///
    /// "No column" is said rather than left blank. A board a ticket was
    /// added to and never sorted is the common case, and an empty gap
    /// there reads as something that failed to load.
    private func badge(_ project: LinkedProject) -> some View {
        let colour = project.statusColor
        return Text(project.status ?? "No column")
            .font(.system(size: 11))
            .foregroundStyle(colour?.tint ?? Color(nsColor: .secondaryLabelColor))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                colour.map { Ink.wash($0.system) }
                    ?? Color(nsColor: .quaternaryLabelColor).opacity(0.5),
                in: Capsule()
            )
    }

    /// Regular by default, and bold only where the colour already says
    /// the chip is the loud one. Without a retina screen to draw it on,
    /// a bold face at eleven points is smeared rather than emphasised.
    private func chip(
        _ content: some View,
        fill: Color? = nil,
        ink: AnyShapeStyle = AnyShapeStyle(.primary),
        weight: Font.Weight = .regular
    ) -> some View {
        content
            .font(.system(size: 11, weight: weight))
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                fill ?? Color(nsColor: .quaternaryLabelColor).opacity(0.5),
                in: Capsule()
            )
    }

    /// Named even when nobody is named: "nobody is on this" is the answer
    /// somebody opens a ticket for as often as a name is, and a line that
    /// simply leaves it out cannot tell the two apart.
    private var assigned: String {
        assignees.isEmpty ? "unassigned" : assignees.joined(separator: ", ")
    }
}


/// What a board chip needs to change the column it names: who to ask,
/// and which issue it is about.
///
/// Its own type rather than `PaneWriting`: this write is gated on a scope
/// of its own, and a pane that may set labels may well not be allowed to
/// move anything on a board.
struct BoardWriting {
    let controller: RefreshController
    let issueID: String
}
