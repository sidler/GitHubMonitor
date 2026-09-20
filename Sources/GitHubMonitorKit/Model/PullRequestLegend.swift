import Foundation

/// One entry of the legend under a pull request list.
public enum LegendSymbol: Hashable, Sendable, Identifiable {
    /// The pull request's own review decision.
    case review(ReviewDecision)
    case checks(ChecksStatus)
    /// One of the reviewer counts in a row.
    case reviewers(ReviewTallyKind)
    case draft

    public var id: String {
        switch self {
        case .review(let decision): "review.\(decision.rawValue)"
        case .checks(let status): "checks.\(status.rawValue)"
        case .reviewers(let kind): "reviewers.\(kind.rawValue)"
        case .draft: "draft"
        }
    }

    /// Nil for the draft badge, which is its own legend entry and carries no
    /// symbol of its own.
    public var symbolName: String? {
        switch self {
        case .review(let decision): decision.symbolName
        case .checks(let status): status.symbolName
        case .reviewers(let kind): kind.symbolName
        case .draft: nil
        }
    }

    /// Short wording, printed beside the symbol.
    ///
    /// One word wherever a word will do: a status bar cannot hold eleven
    /// phrases, and the tooltip carries the sentence anyway.
    public var label: String {
        switch self {
        case .review(let decision):
            switch decision {
            case .approved: "approved"
            case .changesRequested: "changes"
            case .reviewRequired: "required"
            case .none: "no review"
            }
        case .checks(let status):
            switch status {
            case .success: "passed"
            case .failure: "failed"
            case .pending: "running"
            case .none: "no checks"
            }
        case .reviewers(let kind): kind.legendLabel
        case .draft: "draft"
        }
    }

    /// The fuller wording, for the tooltip -- a legend that has to be short
    /// enough to fit a status bar cannot also be self-explanatory.
    public var help: String {
        switch self {
        case .review(let decision): "The pull request as a whole: \(decision.label.lowercased())"
        case .checks(let status): status.label
        case .reviewers(let kind): kind.legendHelp
        case .draft: "Marked as a draft, so it is not asking for review yet"
        }
    }
}

/// Builds the legend under a pull request list.
///
/// Only the symbols the list on screen actually uses: a fixed legend would
/// spend a status bar's width explaining states that are not there, and the
/// one symbol a reader is puzzling over would be no easier to find.
public enum PullRequestLegend {
    public static func symbols(for items: [PullRequestItem]) -> [LegendSymbol] {
        guard !items.isEmpty else { return [] }

        var result: [LegendSymbol] = []

        let decisions = Set(items.map(\.reviewDecision))
        result += ReviewDecision.allCases.filter(decisions.contains).map(LegendSymbol.review)

        let checks = Set(items.map(\.checks))
        result += ChecksStatus.allCases.filter(checks.contains).map(LegendSymbol.checks)

        let tallies = Set(items.flatMap { $0.reviews.entries.map(\.kind) })
        result += ReviewTallyKind.allCases.filter(tallies.contains).map(LegendSymbol.reviewers)

        if items.contains(where: \.isDraft) { result.append(.draft) }

        return result
    }
}
