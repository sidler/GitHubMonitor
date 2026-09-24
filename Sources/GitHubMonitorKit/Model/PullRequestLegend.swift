import Foundation

/// One entry of the legend under a pull request list.
public enum LegendSymbol: Hashable, Sendable, Identifiable {
    /// The pull request's own review decision.
    case review(ReviewDecision)
    case checks(ChecksStatus)
    /// Whether it still merges.
    case merge(MergeStatus)
    /// One of the reviewer counts in a row.
    case reviewers(ReviewTallyKind)
    case draft
    /// How much has been said on an issue.
    case comments
    /// The milestone an issue belongs to.
    case milestone

    public var id: String {
        switch self {
        case .review(let decision): "review.\(decision.rawValue)"
        case .checks(let status): "checks.\(status.rawValue)"
        case .merge(let status): "merge.\(status.rawValue)"
        case .reviewers(let kind): "reviewers.\(kind.rawValue)"
        case .draft: "draft"
        case .comments: "comments"
        case .milestone: "milestone"
        }
    }

    /// Nil for the draft badge, which is its own legend entry and carries no
    /// symbol of its own.
    public var symbolName: String? {
        switch self {
        case .review(let decision): decision.symbolName
        case .checks(let status): status.symbolName
        case .merge(let status): status.symbolName
        case .reviewers(let kind): kind.symbolName
        case .draft: nil
        case .comments: "bubble.left"
        case .milestone: "flag"
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
        case .merge(let status):
            switch status {
            case .mergeable: "merges"
            case .conflicting: "conflicts"
            case .unknown: "merge unknown"
            }
        case .reviewers(let kind): kind.legendLabel
        case .draft: "draft"
        case .comments: "comments"
        case .milestone: "milestone"
        }
    }

    /// The fuller wording, for the tooltip -- a legend that has to be short
    /// enough to fit a status bar cannot also be self-explanatory.
    public var help: String {
        switch self {
        case .review(let decision): "The pull request as a whole: \(decision.label.lowercased())"
        case .checks(let status): status.label
        case .merge(let status): status.label
        case .reviewers(let kind): kind.legendHelp
        case .draft: "Marked as a draft, so it is not asking for review yet"
        case .comments: "How many comments the issue has collected"
        case .milestone: "The milestone the issue belongs to"
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

        // Unknown is left out: nothing is drawn for it, so a legend entry
        // would explain a symbol that is not on screen.
        let merges = Set(items.map(\.mergeStatus)).subtracting([.unknown])
        result += MergeStatus.allCases.filter(merges.contains).map(LegendSymbol.merge)

        let tallies = Set(items.flatMap { $0.reviews.entries.map(\.kind) })
        result += ReviewTallyKind.allCases.filter(tallies.contains).map(LegendSymbol.reviewers)

        if items.contains(where: \.isDraft) { result.append(.draft) }

        return result
    }
}

/// Builds the legend under the issue list.
///
/// The same rule as for pull requests: only what the rows on screen are
/// using. Labels have no entry -- they are drawn as their own words, and a
/// legend that explained the word "bug" would be noise.
public enum IssueLegend {
    public static func symbols(for items: [IssueItem]) -> [LegendSymbol] {
        var result: [LegendSymbol] = []
        if items.contains(where: { $0.comments > 0 }) { result.append(.comments) }
        if items.contains(where: { $0.milestone != nil }) { result.append(.milestone) }
        return result
    }
}
