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
        case .approved: .green
        case .changesRequested: .orange
        case .reviewRequired, .none: Color(nsColor: .secondaryLabelColor)
        }
    }
}

extension ChecksStatus {
    var tint: Color {
        switch self {
        case .success: .green
        case .failure: .red
        case .pending: .yellow
        case .none: Color(nsColor: .secondaryLabelColor)
        }
    }
}

extension ReviewTallyKind {
    var tint: Color {
        switch self {
        case .accepted: .green
        case .declined: .orange
        // The others report a verdict; this one reports an absence.
        case .pending: Color(nsColor: .secondaryLabelColor)
        }
    }
}

extension LegendSymbol {
    var tint: Color {
        switch self {
        case .review(let decision): decision.tint
        case .checks(let status): status.tint
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
    /// Dark mode keeps the system colour: the same shift there would push
    /// the line towards the title it is meant to sit behind.
    ///
    /// A concrete colour rather than `.secondary`, like everything else a
    /// row draws: inside a selected row SwiftUI resolves hierarchical
    /// styles to white.
    static let rowDetail = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .secondaryLabelColor
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

/// Explains the symbols the list above is using.
///
/// Drops the wording before it drops the symbols: one line only, since the
/// bar it sits in has to keep the same height as the detail pane's beside
/// it. Where the labels do not fit, the tooltips still answer the question.
struct LegendBar: View {
    let symbols: [LegendSymbol]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(symbols, labelled: true)
            row(symbols, labelled: false)
        }
    }

    private func row(_ symbols: [LegendSymbol], labelled: Bool) -> some View {
        HStack(spacing: labelled ? 9 : 6) {
            ForEach(symbols) { symbol in
                HStack(spacing: 3) {
                    mark(symbol)
                    if labelled {
                        Text(symbol.label)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .help(symbol.help)
            }
        }
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
    /// GitHub's palette, in the system colours closest to it. Concrete
    /// values, like everything else a row draws: inside a selected row
    /// SwiftUI resolves hierarchical styles to white.
    var tint: Color {
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
            .background(type.color.tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(type.color.tint.opacity(0.45), lineWidth: 1))
            .help("Issue type: \(type.name)")
    }
}
