import Foundation

/// One remark somebody has written but not sent.
public struct DraftComment: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let path: String
    /// The line in the file its side names, which is what GitHub wants
    /// when the review is finally sent.
    public let line: Int
    public let side: ReviewThread.Side
    public var body: String
    public var writtenAt: Date

    public init(
        id: UUID = UUID(),
        path: String,
        line: Int,
        side: ReviewThread.Side = .new,
        body: String,
        writtenAt: Date = .now
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.body = body
        self.writtenAt = writtenAt
    }
}

/// A review somebody is part way through writing.
///
/// Remarks are collected and sent together, the way GitHub means a review
/// to work: a reviewer reads a diff, says several things, and then says
/// what they think of the whole. Sending each one as it is written would
/// notify the author five times about one reading.
///
/// Bound to a commit, like the approval. The remarks were written against
/// particular lines of a particular diff; if somebody pushes while the
/// review is half written, those line numbers now point at other code,
/// and sending them anyway would attach somebody's words to something
/// they never read.
public struct ReviewDraft: Hashable, Sendable, Codable {
    /// Bumped when the shape of what is written changes, so an old file
    /// is ignored rather than half-read.
    public static let currentSchema = 1

    public var schema: Int
    public let pullRequestID: String
    /// What the diff was when the first remark was written.
    public let commit: String?
    public var comments: [DraftComment]

    public init(
        schema: Int = ReviewDraft.currentSchema,
        pullRequestID: String,
        commit: String?,
        comments: [DraftComment] = []
    ) {
        self.schema = schema
        self.pullRequestID = pullRequestID
        self.commit = commit
        self.comments = comments
    }

    public var isEmpty: Bool { comments.isEmpty }

    /// The remarks on one file, in the order they run down it.
    public func comments(in path: String) -> [DraftComment] {
        comments
            .filter { $0.path == path }
            .sorted { ($0.line, $0.writtenAt) < ($1.line, $1.writtenAt) }
    }

    /// What the button that sends it says.
    public var summary: String {
        comments.count == 1 ? "1 remark" : "\(comments.count) remarks"
    }

    public mutating func add(_ comment: DraftComment) {
        comments.append(comment)
    }

    /// Replaces the words of one remark, or removes it where they have
    /// been rubbed out -- a remark with nothing in it is not a remark,
    /// and GitHub would refuse it anyway.
    public mutating func change(_ id: UUID, to body: String) {
        let written = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        if written.isEmpty {
            comments.remove(at: index)
        } else {
            comments[index].body = written
            comments[index].writtenAt = .now
        }
    }

    public mutating func remove(_ id: UUID) {
        comments.removeAll { $0.id == id }
    }
}
