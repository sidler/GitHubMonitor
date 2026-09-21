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
        case .draft: Color(nsColor: .secondaryLabelColor)
        }
    }
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

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content()
                .font(.caption)
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
