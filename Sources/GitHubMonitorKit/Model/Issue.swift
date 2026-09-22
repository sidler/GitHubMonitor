import Foundation

/// A label on an issue, in the colour GitHub draws it.
public struct IssueLabel: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    /// Six hex digits, as GitHub reports them -- without a leading "#".
    public let color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }

    /// The colour as fractions of one, or nil for anything this does not
    /// understand -- a label whose colour cannot be read is still a label.
    public var components: (red: Double, green: Double, blue: Double)? {
        let hex = color
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// Whether dark text reads better on this colour than white.
    ///
    /// GitHub's palette runs from near-black to near-white, so one fixed
    /// foreground colour makes half the labels unreadable. The weights are
    /// the usual luminance ones: the eye is far more sensitive to green than
    /// to blue.
    public var prefersDarkText: Bool {
        guard let components else { return true }
        let luminance =
            0.299 * components.red + 0.587 * components.green + 0.114 * components.blue
        return luminance > 0.6
    }
}

/// An issue assigned to the user.
///
/// Deliberately not a `PullRequestItem` with the pull request parts left
/// empty: an issue has no draft state, no checks and no reviewers, and a
/// shared type would carry four fields that are always zero here and make
/// every list read them.
public struct IssueItem: Identifiable, Hashable, Sendable, ListedItem {
    public let id: String
    public let number: Int
    public let title: String
    /// "owner/name"
    public let repository: String
    public let author: String
    public let authorAvatarURL: URL?
    public let url: URL
    public let createdAt: Date
    public let updatedAt: Date
    /// How much has been said on it -- the only signal in a row that
    /// something is moving.
    public let comments: Int
    public let labels: [IssueLabel]
    /// Nil when the issue is in no milestone, which most are.
    public let milestone: String?

    public init(
        id: String,
        number: Int,
        title: String,
        repository: String,
        author: String,
        authorAvatarURL: URL?,
        url: URL,
        createdAt: Date? = nil,
        updatedAt: Date,
        comments: Int = 0,
        labels: [IssueLabel] = [],
        milestone: String? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.repository = repository
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.url = url
        self.createdAt = createdAt ?? updatedAt
        self.updatedAt = updatedAt
        self.comments = comments
        self.labels = labels
        self.milestone = milestone
    }

    /// The timestamp the list is ordered on, as the pull request lists do it:
    /// one switch in the toolbar orders every list, since they answer the
    /// same question about different things.
    public func date(for sort: PullRequestSort) -> Date {
        switch sort {
        case .updated: updatedAt
        case .created: createdAt
        }
    }
}

/// One comment on an issue, as the detail pane shows it.
public struct IssueComment: Identifiable, Hashable, Sendable {
    public let id: String
    public let author: String
    public let avatarURL: URL?
    public let createdAt: Date
    public let body: String

    public init(id: String, author: String, avatarURL: URL?, createdAt: Date, body: String) {
        self.id = id
        self.author = author
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.body = body
    }
}

/// What the detail pane shows for one issue, fetched when its row is opened.
public struct IssueDetail: Hashable, Sendable {
    /// The issue's own text. Empty when it was opened with a title only.
    public let body: String
    /// The newest comments, oldest of those first, so the thread reads
    /// downwards the way it does on GitHub.
    public let comments: [IssueComment]
    /// Every comment, including the ones not fetched -- the pane says so
    /// rather than pretending the thread is as short as what it shows.
    public let totalComments: Int

    public init(body: String, comments: [IssueComment], totalComments: Int) {
        self.body = body
        self.comments = comments
        self.totalComments = totalComments
    }

    /// How many comments came before the ones on screen.
    public var olderComments: Int { max(0, totalComments - comments.count) }
}

/// Lifecycle of a lazily fetched issue detail.
public enum IssueDetailState: Equatable, Sendable {
    case loading
    case loaded(IssueDetail)
    case failed(String)
}
