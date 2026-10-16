import Foundation

/// One commit of a pull request, as the pane lists them.
public struct PullRequestCommit: Identifiable, Hashable, Sendable {
    public let oid: String
    /// What GitHub itself abbreviates it to, which is not always seven
    /// characters: it lengthens them until they are unambiguous in that
    /// repository.
    public let abbreviated: String
    /// The first line of the message, which is the whole message in a
    /// repository whose commits are written properly and the only part
    /// worth a row otherwise.
    public let headline: String
    public let author: String
    public let avatarURL: URL?
    public let committedAt: Date
    /// What this commit's own checks said.
    ///
    /// The point of the list rather than a detail of it: a pull request
    /// says whether it is green now, and this says since when.
    public let checks: ChecksStatus
    public let url: URL?

    public var id: String { oid }

    public init(
        oid: String,
        abbreviated: String? = nil,
        headline: String,
        author: String = "",
        avatarURL: URL? = nil,
        committedAt: Date = .distantPast,
        checks: ChecksStatus = .none,
        url: URL? = nil
    ) {
        self.oid = oid
        self.abbreviated = abbreviated ?? String(oid.prefix(7))
        self.headline = headline
        self.author = author
        self.avatarURL = avatarURL
        self.committedAt = committedAt
        self.checks = checks
        self.url = url
    }
}

/// A pull request's commits, fetched only once somebody asks for them.
public enum CommitsState: Equatable, Sendable {
    case loading
    case loaded([PullRequestCommit])
    case failed(String)
}
