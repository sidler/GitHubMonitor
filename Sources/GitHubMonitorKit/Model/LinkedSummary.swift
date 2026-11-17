import Foundation
import SwiftUI

/// Enough of a linked issue or pull request to answer "what is this about"
/// without leaving what you were reading.
///
/// One type for both kinds. They differ in what is worth saying about them
/// -- labels against checks, a milestone against a branch -- but the
/// question being asked of them is the same, and so is the panel.
/// A board an item sits on, and which column of it.
///
/// The column is what anybody asks a board for -- "is it in review yet"
/// -- and it is optional because a board need not have a Status field at
/// all. The project is named either way, since being on a board is itself
/// an answer.
public struct LinkedProject: Hashable, Sendable {
    public let title: String
    public let status: String?

    public init(title: String, status: String? = nil) {
        self.title = title
        self.status = status
    }

    public var label: String {
        guard let status else { return title }
        return "\(title) \u{00b7} \(status)"
    }
}

public struct LinkedSummary: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case issue
        case pullRequest
    }

    /// Where the item stands. Drawn from two different GraphQL enums plus
    /// the draft flag, because "open" on a pull request nobody may merge
    /// yet is not the same answer as "open".
    public enum State: Hashable, Sendable {
        case open
        case draft
        case merged
        case closed
        /// An issue closed as not planned, which is not the same as done.
        case notPlanned

        public var label: String {
            switch self {
            case .open: "Open"
            case .draft: "Draft"
            case .merged: "Merged"
            case .closed: "Closed"
            case .notPlanned: "Closed as not planned"
            }
        }

        /// The colour for where it stands.
        ///
        /// GitHub's own, which is what anybody reading it already expects:
        /// green for open, purple for merged. Everything that is over
        /// without having been merged is grey rather than red -- a closed
        /// issue is not a failure, and a row of red chips would shout.
        /// A concrete grey rather than `.secondary`: inside a selected
        /// row SwiftUI resolves a hierarchical style against the
        /// selection, and the badge came out white on white. The same
        /// trap `ReviewDecision.tint` carries a warning about.
        public var tint: Color {
            switch self {
            case .open: Ink.green
            case .merged: Ink.purple
            case .draft, .closed, .notPlanned: Ink.gray
            }
        }

    }

    public let reference: ItemReference
    public let kind: Kind
    public let state: State
    public let title: String
    public let author: String
    public let authorAvatarURL: URL?
    /// Who it is on, which for an issue is the question the panel is
    /// usually open to answer. Empty where nobody has been named.
    public let assignees: [String]
    /// The boards it sits on. Empty where it is on none -- and also where
    /// the token cannot see boards at all, which is why nothing is drawn
    /// for the empty case.
    public let projects: [LinkedProject]
    public let url: URL
    public let createdAt: Date
    public let updatedAt: Date
    public let body: String
    public let comments: Int
    /// Issues only; a pull request's labels are not what anyone opens this
    /// panel for.
    public let labels: [IssueLabel]
    /// Pull requests only.
    public let checks: ChecksStatus?
    public let reviewDecision: ReviewDecision?
    public let changedFiles: Int?
    public let additions: Int?
    public let deletions: Int?

    public var id: String { reference.id }

    /// The glyph for what this is and where it stands.
    ///
    /// Both at once, because neither answers alone: a closed issue and a
    /// closed pull request are different news, and GitHub draws them
    /// differently for that reason.
    public var symbolName: String { Self.symbolName(kind: kind, state: state) }

    /// The same, for anything that has a kind and a state but is not a
    /// whole summary -- a sub-issue row, for one. One place, so a closed
    /// issue wears the same tick wherever it is drawn.
    public static func symbolName(kind: Kind, state: State) -> String {
        switch (kind, state) {
        case (.issue, .open): "circle"
        case (.issue, .closed): "checkmark.circle.fill"
        case (.issue, .notPlanned): "slash.circle"
        case (.pullRequest, .merged): "arrow.triangle.merge"
        case (.pullRequest, .closed): "xmark.circle.fill"
        case (.pullRequest, .draft): "circle.dashed"
        case (.pullRequest, .open): "arrow.triangle.pull"
        // A pull request is never "not planned" and an issue is never a
        // draft or merged, but the switch has to say something.
        default: "circle"
        }
    }

    public init(
        reference: ItemReference,
        kind: Kind,
        state: State,
        title: String,
        author: String,
        authorAvatarURL: URL? = nil,
        assignees: [String] = [],
        projects: [LinkedProject] = [],
        url: URL,
        createdAt: Date,
        updatedAt: Date,
        body: String = "",
        comments: Int = 0,
        labels: [IssueLabel] = [],
        checks: ChecksStatus? = nil,
        reviewDecision: ReviewDecision? = nil,
        changedFiles: Int? = nil,
        additions: Int? = nil,
        deletions: Int? = nil
    ) {
        self.reference = reference
        self.kind = kind
        self.state = state
        self.title = title
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.assignees = assignees
        self.projects = projects
        self.url = url
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.body = body
        self.comments = comments
        self.labels = labels
        self.checks = checks
        self.reviewDecision = reviewDecision
        self.changedFiles = changedFiles
        self.additions = additions
        self.deletions = deletions
    }
}

/// Lifecycle of one looked-up link.
///
/// `missing` is its own case rather than a failure: a number read out of a
/// sentence may simply not be an issue, and that is an answer, not an
/// error. Nothing is drawn for it.
public enum LinkedSummaryState: Equatable, Sendable {
    case loading
    case loaded(LinkedSummary)
    case missing
    case failed(String)
}
