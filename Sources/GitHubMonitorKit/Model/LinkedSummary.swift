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
    /// The three ids a column change needs. GitHub's mutation takes ids
    /// and will not take names, the way the label ones do.
    ///
    /// All nil where the token may read boards but not write them, which
    /// is what `read:project` alone grants -- so the chip knows to stay a
    /// chip rather than offering a menu that would be refused.
    public let projectID: String?
    public let itemID: String?
    public let statusFieldID: String?
    /// Which column it is in, by id rather than by name: it is what ticks
    /// the menu and what the chip takes its colour from.
    public let statusOptionID: String?
    /// The columns the board has, for the menu to list.
    ///
    /// Asked of the project rather than read off the item's own value: an
    /// issue sitting on a board with no column yet has no value to read
    /// them from, and that is exactly the issue somebody wants to move.
    public let statuses: [ProjectStatus]

    public init(
        title: String,
        status: String? = nil,
        projectID: String? = nil,
        itemID: String? = nil,
        statusFieldID: String? = nil,
        statusOptionID: String? = nil,
        statuses: [ProjectStatus] = []
    ) {
        self.title = title
        self.status = status
        self.projectID = projectID
        self.itemID = itemID
        self.statusFieldID = statusFieldID
        self.statusOptionID = statusOptionID
        self.statuses = statuses
    }

    /// The colour the board itself paints this column in, nil where there
    /// is no column to paint.
    ///
    /// By id, then by name, then grey: a board read without its options
    /// has a column name and no palette to look it up in, and grey is the
    /// honest answer rather than a wrong hue.
    public var statusColor: IssueTypeColor? {
        guard status != nil else { return nil }
        let option = statuses.first { $0.id == statusOptionID }
            ?? statuses.first { $0.name == status }
        return option?.color ?? .gray
    }

    public var label: String {
        guard let status else { return title }
        return "\(title) \u{00b7} \(status)"
    }

    /// Whether the column can be changed from here at all.
    public var isSettable: Bool {
        projectID != nil && itemID != nil && statusFieldID != nil && !statuses.isEmpty
    }

    /// The same boards with one of them in another column, for showing a
    /// move before GitHub has agreed to it.
    ///
    /// Matched on the item rather than the title: an issue sits on a
    /// board once, but two boards can read alike, and moving an issue on
    /// one of them must not move the chip beside it.
    public static func after(
        _ boards: [LinkedProject], moving item: String, to status: ProjectStatus
    ) -> [LinkedProject] {
        boards.map { $0.itemID == item ? $0.moved(to: status) : $0 }
    }

    /// The same board in a different column.
    ///
    /// The whole column, not its name: the chip takes its colour and the
    /// menu its tick from the id, and a move that carried only the name
    /// would leave both showing the column it came from.
    public func moved(to status: ProjectStatus) -> LinkedProject {
        LinkedProject(
            title: title, status: status.name, projectID: projectID, itemID: itemID,
            statusFieldID: statusFieldID, statusOptionID: status.id, statuses: statuses
        )
    }
}

/// One column of a board, by the id the mutation takes.
public struct ProjectStatus: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// GitHub paints a board column from the same eight it paints an
    /// issue type from, under the same names -- so this is that type
    /// rather than a second copy of it.
    public let color: IssueTypeColor

    public init(id: String, name: String, color: IssueTypeColor = .gray) {
        self.id = id
        self.name = name
        self.color = color
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
