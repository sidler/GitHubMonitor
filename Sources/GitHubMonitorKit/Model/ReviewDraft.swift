import Foundation

/// One remark somebody has written but not sent.
public struct DraftComment: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let path: String
    /// The line in the file its side names, which is what GitHub wants
    /// when the review is finally sent.
    public let line: Int
    public let side: ReviewThread.Side
    /// The conversation this answers, where it answers one.
    ///
    /// Nil for a remark that starts its own. The file and line are
    /// filled in either way -- a reply belongs to a place in the diff as
    /// much as a new remark does, and that is where it is drawn.
    ///
    /// Optional rather than a second kind of comment, so a draft written
    /// before replies existed still reads: a missing field decodes as
    /// nil, which is exactly what those drafts are.
    public let replyTo: String?
    public var body: String
    public var writtenAt: Date

    public var isReply: Bool { replyTo != nil }

    public init(
        id: UUID = UUID(),
        path: String,
        line: Int,
        side: ReviewThread.Side = .new,
        replyTo: String? = nil,
        body: String,
        writtenAt: Date = .now
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.replyTo = replyTo
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
    /// What this review says about the whole pull request, which GitHub
    /// calls the review's body and shows above the remarks.
    ///
    /// Not bound to a line, so it survives a push the way the remarks
    /// cannot -- but it travels with them, because it is the same act.
    public var body: String
    /// A remark for the conversation tab rather than for the review: the
    /// same pot the pane reads its comments from.
    ///
    /// Held here rather than posted as it is written, so that one press
    /// sends everything somebody wrote while reading. It goes out beside
    /// the review and not inside it -- GitHub keeps the two apart, and
    /// so does this.
    public var conversation: String

    public init(
        schema: Int = ReviewDraft.currentSchema,
        pullRequestID: String,
        commit: String?,
        comments: [DraftComment] = [],
        body: String = "",
        conversation: String = ""
    ) {
        self.schema = schema
        self.pullRequestID = pullRequestID
        self.commit = commit
        self.comments = comments
        self.body = body
        self.conversation = conversation
    }

    /// Read by hand so that a draft written before these two texts
    /// existed still reads. Bumping the schema instead would have been
    /// one line and would have thrown away every review somebody was
    /// part way through writing.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(Int.self, forKey: .schema)
        pullRequestID = try values.decode(String.self, forKey: .pullRequestID)
        commit = try values.decodeIfPresent(String.self, forKey: .commit)
        comments = try values.decodeIfPresent([DraftComment].self, forKey: .comments) ?? []
        body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
        conversation = try values.decodeIfPresent(String.self, forKey: .conversation) ?? ""
    }

    /// Nothing written anywhere. A review that is only a sentence about
    /// the whole is still a review, so the two texts count.
    public var isEmpty: Bool {
        comments.isEmpty && Self.written(body).isEmpty && Self.written(conversation).isEmpty
    }

    static func written(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The review's own words, or nil where there are none -- GitHub
    /// takes no body rather than an empty one.
    public var writtenBody: String? {
        let written = Self.written(body)
        return written.isEmpty ? nil : written
    }

    /// Whether anything here can travel inside a review.
    ///
    /// Narrower than "something is written", and the difference is the
    /// conversation remark: that one goes out as a comment beside the
    /// review, never within it. A draft holding only that has nothing
    /// for a review to say -- and GitHub refuses a change request with
    /// no words, so a button that offered to send one would post the
    /// remark and then fail on the review behind it.
    public var hasReviewWords: Bool { !comments.isEmpty || writtenBody != nil }

    /// The conversation remark, or nil where there is none.
    public var writtenConversation: String? {
        let written = Self.written(conversation)
        return written.isEmpty ? nil : written
    }

    /// The remarks on one file, in the order they run down it.
    public func comments(in path: String) -> [DraftComment] {
        comments
            .filter { $0.path == path }
            .sorted { ($0.line, $0.writtenAt) < ($1.line, $1.writtenAt) }
    }

    /// How many unsent remarks stand on each file.
    ///
    /// For the tree beside the diff, which is what somebody scans to
    /// decide where to go next -- and their own unsent remarks are as
    /// good a reason to go somewhere as anybody else's.
    public var countsByPath: [String: Int] {
        comments.reduce(into: [:]) { counts, comment in
            counts[comment.path, default: 0] += 1
        }
    }

    /// What the button that sends it says.
    public var summary: String {
        comments.count == 1 ? "1 remark" : "\(comments.count) remarks"
    }

    public mutating func add(_ comment: DraftComment) {
        comments.append(comment)
    }

    /// The remarks that start a conversation, which are the only ones a
    /// review can carry as `threads`.
    public var openings: [DraftComment] { comments.filter { !$0.isReply } }

    /// The ones that answer a conversation somebody else began.
    public var replies: [DraftComment] { comments.filter(\.isReply) }

    /// What this draft answers in one thread, oldest first.
    public func replies(to threadID: String) -> [DraftComment] {
        comments.filter { $0.replyTo == threadID }.sorted { $0.writtenAt < $1.writtenAt }
    }

    /// Whether sending it needs the long way round.
    ///
    /// A review carries the remarks that open a conversation in the one
    /// request that creates it. A reply cannot go that way -- it names a
    /// thread, and the mutation that writes one wants a review to put it
    /// in. So a draft of openings alone keeps the single request it
    /// always had, and only one with replies in it pays for the detour.
    public var needsPendingReview: Bool { !replies.isEmpty }

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
