import SwiftUI

/// The colours the row symbols are drawn in.
///
/// Here rather than inside the row so the legend can use the same ones: a
/// legend printed in different colours from the list it explains is worse
/// than none.
///
/// Concrete colours throughout, including where `.secondary` would read
/// better: inside a selected row SwiftUI resolves hierarchical styles
/// against the selection, and the symbols came out white.
extension ReviewDecision {
    var tint: Color {
        switch self {
        case .approved: Ink.green
        case .changesRequested: Ink.orange
        case .reviewRequired, .none: Ink.gray
        }
    }
}

extension ChecksStatus {
    var tint: Color {
        switch self {
        case .success: Ink.green
        case .failure: Ink.red
        case .pending: Ink.yellow
        case .none: Ink.gray
        }
    }
}

extension WaitingAge {
    /// Orange, then red: the two steps the checks and the review decision
    /// already use, so a colour keeps meaning roughly what it did.
    var tint: Color {
        switch self {
        case .fresh: Color.rowDetail
        case .aging: Ink.orange
        case .overdue: Ink.red
        }
    }
}

extension ReviewState {
    /// What one reviewer has said, in the same two steps the checks use.
    ///
    /// Commented and dismissed are grey rather than a colour of their
    /// own: neither is an answer to the question the pane is asking, and
    /// a third hue beside the two that are would only crowd it.
    var tint: Color {
        switch self {
        case .approved: Ink.green
        case .changesRequested: Ink.orange
        case .pending: Ink.yellow
        case .commented, .dismissed: Ink.gray
        }
    }
}

extension MergeStatus {
    var tint: Color {
        switch self {
        // Green is affordable here: only the detail pane draws this one,
        // and there it is one line about one pull request. The lists draw
        // the conflict and nothing else.
        case .mergeable: Ink.green
        case .conflicting: Ink.red
        case .unknown: Color(nsColor: .tertiaryLabelColor)
        }
    }
}

extension ReviewTallyKind {
    var tint: Color {
        switch self {
        case .accepted: Ink.green
        case .declined: Ink.orange
        // The others report a verdict; this one reports an absence.
        case .pending: Ink.gray
        }
    }
}

extension ReviewThread {
    /// The colour of the rule down a thread's left edge.
    ///
    /// Three states, in the order they answer "does this still want
    /// something from me": outdated first, because a remark about code
    /// that has since been rewritten is a different question from one
    /// about code that is still there -- and a thread can be both
    /// outdated and resolved, in which case the older fact is the one
    /// worth naming. Then resolved, then the ordinary open one.
    var tint: Color {
        if isOutdated { return Ink.orange }
        if isResolved { return Ink.gray }
        return Ink.blue
    }
}

extension LegendSymbol {
    var tint: Color {
        switch self {
        case .review(let decision): decision.tint
        case .checks(let status): status.tint
        case .merge(let status): status.tint
        case .reviewers(let kind): kind.tint
        case .draft, .comments, .milestone: Color(nsColor: .secondaryLabelColor)
        }
    }
}

extension Color {
    /// The second line of a row: repository, number, author, dates.
    ///
    /// Darker than the system's secondary label in light mode, where that
    /// grey on a white list is light enough to be hard work at this size.
    /// Lighter than it in dark mode, where the system grey falls to 3.3 to
    /// one against the grey of a selected row -- the one place a row is
    /// not drawn on the page's own colour.
    ///
    /// A concrete colour rather than `.secondary`, like everything else a
    /// row draws: inside a selected row SwiftUI resolves hierarchical
    /// styles to white.
    static let rowDetail = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.788, green: 0.788, blue: 0.788, alpha: 1)
            : NSColor.labelColor.withAlphaComponent(0.68)
    })
}

/// The strip along the bottom of a column: the content's status bar, and
/// the detail pane's actions.
///
/// One definition because they sit side by side and are read as a single
/// strip. Each had its own font and padding, and the difference showed as a
/// step where the columns meet. The height is fixed rather than left to the
/// contents for the same reason: what is in one column must not move the
/// other's edge.
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    /// Tall enough for the tallest thing any of these bars holds, which is
    /// the legend's symbols at 27 points.
    static var height: CGFloat { 28 }

    /// One size for everything along the bottom edge.
    ///
    /// A font alone was not enough: a button in the accessory bar style
    /// takes its size from the control size rather than the inherited font,
    /// so the sidebar's "Settings" and the detail pane's actions came out a
    /// couple of points larger than the counts between them. Both are set
    /// here, and both land on the same 11 points.
    static var font: Font { .subheadline }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content()
                .font(Self.font)
                .controlSize(.small)
                .padding(.horizontal, 12)
                // Padding first, then the frame: the other way round the
                // bar asks for the window's width plus its own margins.
                // A fixed height, not a minimum: what one column puts in
                // its bar must not move the other column's edge.
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.height)
                .background(.bar)
        }
    }
}

/// The draft marker, as the rows draw it.
struct DraftBadge: View {
    var body: some View {
        Text("DRAFT")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 3))
    }
}

/// Explains the symbols the list above is using, and narrows it to them.
///
/// Drops the wording before it drops the symbols: one line only, since the
/// bar it sits in has to keep the same height as the detail pane's beside
/// it. Where the labels do not fit, the tooltips still answer the question.
///
/// Pressing one shows only the rows carrying it, and pressing it again
/// puts the rest back. A legend is already a list of the states in front
/// of you; being able to press one is the shortest way from "three of
/// these have failing checks" to seeing which three.
struct LegendBar: View {
    let symbols: [LegendSymbol]
    /// The symbol the list is narrowed to, if any.
    var active: LegendSymbol?
    /// Nil leaves the legend what it was: something to read.
    var choose: ((LegendSymbol?) -> Void)?

    /// The symbol being filtered by stays in the legend even once nothing
    /// carries it any more -- a refresh can fix the last failing check --
    /// or the only way back would be to leave the list and come back.
    private var shown: [LegendSymbol] {
        guard let active, !symbols.contains(active) else { return symbols }
        return symbols + [active]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(shown, labelled: true)
            row(shown, labelled: false)
        }
    }

    private func row(_ symbols: [LegendSymbol], labelled: Bool) -> some View {
        HStack(spacing: labelled ? 9 : 6) {
            ForEach(symbols) { symbol in
                entry(symbol, labelled: labelled)
            }
        }
    }

    @ViewBuilder
    private func entry(_ symbol: LegendSymbol, labelled: Bool) -> some View {
        if let choose {
            Button {
                choose(active == symbol ? nil : symbol)
            } label: {
                wording(symbol, labelled: labelled)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(
                active == symbol
                    ? "\(symbol.help) \u{2014} showing only these; press again for the rest"
                    : "\(symbol.help) \u{2014} press to show only these"
            )
            // A row of bare symbols has nothing for a screen reader to
            // read out, and these are buttons now rather than marks on a
            // page.
            .accessibilityLabel(symbol.label)
            .accessibilityHint(
                active == symbol ? "Shows the rest of the list again" : symbol.help
            )
            .accessibilityAddTraits(active == symbol ? [.isSelected] : [])
        } else {
            wording(symbol, labelled: labelled)
                .help(symbol.help)
        }
    }

    /// Lit, it wears a wash of the symbol's own colour. Which colour says
    /// what is being filtered by without a second mark to read, and the
    /// wash is faint enough that an unpressed legend still looks like a
    /// legend rather than a row of buttons.
    private func wording(_ symbol: LegendSymbol, labelled: Bool) -> some View {
        HStack(spacing: 3) {
            mark(symbol)
            if labelled {
                Text(symbol.label)
                    .foregroundStyle(active == symbol ? symbol.tint : .secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, active == symbol ? 5 : 0)
        .padding(.vertical, active == symbol ? 1 : 0)
        .background {
            if active == symbol {
                Capsule().fill(symbol.tint.opacity(0.16))
            }
        }
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func mark(_ symbol: LegendSymbol) -> some View {
        if let symbolName = symbol.symbolName {
            Image(systemName: symbolName)
                .foregroundStyle(symbol.tint)
        } else {
            DraftBadge()
        }
    }
}

/// A label as GitHub draws it: its own colour, with text that stays
/// readable on it.
///
/// The colour is the label's meaning here -- teams pick red for breakage and
/// green for done -- so a monochrome chip would throw away the fastest thing
/// in the row to read.
/// Whether a label in a row narrows the list, and which one it is narrowed
/// to now.
///
/// The same bargain the legend at the bottom of the window makes: the mark
/// you read something by is the mark you press to see only those. A label
/// on a row was the one mark in the window that said something about an
/// issue and could not be acted on.
struct LabelFiltering {
    /// The label the list is narrowed to, if any.
    var active: IssueLabel?
    /// Pressing the active one again is what clears it.
    let choose: (IssueLabel) -> Void

    /// By name, not by id: two repositories give the same label different
    /// ids, and a list spanning both should narrow to all of it.
    func isActive(_ label: IssueLabel) -> Bool { active?.name == label.name }
}

/// Deliberately with no "this is the one being filtered by" state. While a
/// label is pressed, every row on screen carries it, so a ring round each
/// of them would be a mark on every chip in the window saying something
/// the list already says by being short. What is pressed is named once, at
/// the top, beside the grouping and the sort.
struct LabelChip: View {
    let label: IssueLabel

    var body: some View {
        Text(label.name)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .help(label.name)
    }

    private var background: Color {
        guard let components = label.components else {
            return Color(nsColor: .quaternaryLabelColor)
        }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    private var foreground: Color {
        label.prefersDarkText ? Color(red: 0.1, green: 0.1, blue: 0.1) : .white
    }
}

extension IssueTypeColor {
    /// The hue itself, for the wash behind the name. Light, while the name
    /// on it is dark: a chip drawn in one colour at two strengths is a
    /// chip nobody can read.
    var system: Color {
        switch self {
        case .gray: Color(nsColor: .secondaryLabelColor)
        case .blue: .blue
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        }
    }

    /// GitHub's palette, in the system colours closest to it. Concrete
    /// values, like everything else a row draws: inside a selected row
    /// SwiftUI resolves hierarchical styles to white.
    var tint: Color {
        switch self {
        case .gray: Ink.gray
        case .blue: Ink.blue
        case .green: Ink.green
        case .yellow: Ink.yellow
        case .orange: Ink.orange
        case .red: Ink.red
        case .pink: Ink.pink
        case .purple: Ink.purple
        }
    }
}

/// The kind of work an issue is: Bug, Task, Feature, Epic.
///
/// Drawn unlike a label on purpose -- tinted and outlined rather than filled
/// -- because it is one value from a short list the organisation maintains,
/// and a row can carry it beside any number of labels without the two being
/// read as the same thing.
struct IssueTypeChip: View {
    let type: IssueType
    var compact = false

    var body: some View {
        Text(type.name)
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(type.color.tint)
            .background(Ink.wash(type.color.system), in: Capsule())
            .overlay(Capsule().strokeBorder(type.color.tint.opacity(0.45), lineWidth: 1))
            .help("Issue type: \(type.name)")
    }
}
