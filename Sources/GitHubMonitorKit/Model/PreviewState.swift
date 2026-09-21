import Foundation

/// Who wrote the comment a notification is about.
///
/// The notifications API itself names nobody -- it reports a thread, not a
/// person. The sender is only known once the comment behind
/// `latest_comment_url` has been read, which is also where the preview
/// comes from, so both arrive together or not at all.
public struct CommentAuthor: Hashable, Sendable {
    public let login: String
    public let avatarURL: URL?

    public init(login: String, avatarURL: URL?) {
        self.login = login
        self.avatarURL = avatarURL
    }
}

/// What came back from a notification's latest comment.
public struct CommentPreview: Hashable, Sendable {
    public let author: CommentAuthor?
    /// Nil where the thread has no body at all -- a review request or a
    /// state change, for instance.
    public let body: String?

    public static let none = CommentPreview(author: nil, body: nil)

    public init(author: CommentAuthor?, body: String?) {
        self.author = author
        self.body = body
    }
}

/// Lifecycle of a lazily fetched comment preview.
public enum PreviewState: Equatable, Sendable {
    case loading
    case loaded(CommentPreview)
    case failed(String)

    /// Convenience for the common case of a body without an author.
    public static func text(_ body: String) -> PreviewState {
        .loaded(CommentPreview(author: nil, body: body))
    }

    public var preview: CommentPreview? {
        if case .loaded(let preview) = self { return preview }
        return nil
    }
}
