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
/// Takes a second line before it drops the wording, and drops the wording
/// before it drops the symbols. A list showing every state at once needs more
/// width than a status bar has, and a row of unlabelled symbols is not a
/// legend; in the narrowest windows the tooltips still answer the question.
struct LegendBar: View {
    let symbols: [LegendSymbol]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(symbols, labelled: true)
            twoLines
            row(symbols, labelled: false)
        }
    }

    private var twoLines: some View {
        // Split evenly rather than by group: the groups here are three and
        // four entries long, and a 7/3 line break wastes the width it was
        // asking for.
        let half = (symbols.count + 1) / 2
        return VStack(alignment: .leading, spacing: 1) {
            row(Array(symbols.prefix(half)), labelled: true)
            row(Array(symbols.dropFirst(half)), labelled: true)
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
