import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Notification parser")
struct NotificationParserTests {
    private func payload(
        id: String = "1",
        reason: String = "mention",
        subjectURL: String? = "https://api.github.com/repos/octo/server/issues/42",
        latestComment: String? = "https://api.github.com/repos/octo/server/issues/comments/9"
    ) -> [String: Any] {
        var subject: [String: Any] = ["title": "Migration order", "type": "Issue"]
        if let subjectURL { subject["url"] = subjectURL }
        if let latestComment { subject["latest_comment_url"] = latestComment }

        return [
            "id": id,
            "reason": reason,
            "updated_at": "2026-09-20T09:00:00Z",
            "subject": subject,
            "repository": [
                "full_name": "octo/server",
                "owner": ["avatar_url": "https://example.com/o.png"],
            ],
        ]
    }

    private func data(_ objects: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: objects)
    }

    @Test("Fields are mapped across")
    func mapping() throws {
        let items = try NotificationParser.notifications(from: data([payload()]))
        let item = try #require(items.first)
        #expect(item.id == "1")
        #expect(item.title == "Migration order")
        #expect(item.repository == "octo/server")
        #expect(item.reason == .mention)
        #expect(item.avatarURL?.absoluteString == "https://example.com/o.png")
        #expect(item.latestCommentAPIURL != nil)
    }

    @Test("Unknown reasons do not drop the notification")
    func unknownReason() throws {
        let items = try NotificationParser.notifications(from: data([payload(reason: "ci_activity")]))
        #expect(items.first?.reason == .other)
    }

    @Test("Team mentions are recognised under their API spelling")
    func teamMention() throws {
        let items = try NotificationParser.notifications(from: data([payload(reason: "team_mention")]))
        #expect(items.first?.reason == .teamMention)
    }

    @Test("A thread without a comment URL still parses")
    func noComment() throws {
        let items = try NotificationParser.notifications(from: data([payload(latestComment: nil)]))
        #expect(items.first?.latestCommentAPIURL == nil)
    }

    @Test("A non-list response is an error, not an empty list")
    func malformedResponse() {
        let data = Data(#"{"message":"Bad credentials"}"#.utf8)
        #expect(throws: GitHubError.self) {
            try NotificationParser.notifications(from: data)
        }
    }

    @Test("Comment bodies are read from either field")
    func commentBodies() {
        #expect(NotificationParser.comment(from: Data(#"{"body":"hello"}"#.utf8)).body == "hello")
        // Commit notifications carry "message" instead of "body".
        #expect(
            NotificationParser.comment(from: Data(#"{"message":"fix: thing"}"#.utf8)).body
                == "fix: thing"
        )
    }

    /// An empty body must read as "no preview", not as an empty bubble.
    @Test("Blank comment bodies count as no body")
    func blankBody() {
        #expect(NotificationParser.comment(from: Data(#"{"body":""}"#.utf8)).body == nil)
        #expect(NotificationParser.comment(from: Data(#"{"body":"   \n "}"#.utf8)).body == nil)
        #expect(NotificationParser.comment(from: Data(#"{}"#.utf8)).body == nil)
    }

    /// The sender is the whole reason the comment is fetched for every row,
    /// not just the one that is open.
    @Test("The sender comes out of the comment")
    func commentAuthor() throws {
        let data = Data(#"{"body":"hi","user":{"login":"mira","avatar_url":"https://e.com/a.png"}}"#.utf8)
        let author = try #require(NotificationParser.comment(from: data).author)
        #expect(author.login == "mira")
        #expect(author.avatarURL?.absoluteString == "https://e.com/a.png")
    }

    /// A commit names an author who is a git identity, and only sometimes a
    /// GitHub account: the name is what there always is.
    @Test("A commit's author is read from its own field")
    func commitAuthor() throws {
        let withAccount = Data(#"{"message":"fix","author":{"login":"dara","avatar_url":"https://e.com/d.png"}}"#.utf8)
        #expect(NotificationParser.comment(from: withAccount).author?.login == "dara")

        let nameOnly = Data(#"{"message":"fix","author":{"name":"Dana Novak"}}"#.utf8)
        let author = try #require(NotificationParser.comment(from: nameOnly).author)
        #expect(author.login == "Dana Novak")
        #expect(author.avatarURL == nil)
    }

    @Test("A thread with no comment names nobody, rather than guessing")
    func noAuthor() {
        #expect(NotificationParser.comment(from: Data(#"{"body":"hi"}"#.utf8)).author == nil)
        #expect(NotificationParser.comment(from: Data("not json".utf8)) == .none)
    }
}

@Suite("Notification links")
struct NotificationLinkTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    /// The API path says "pulls", the website says "pull" -- getting this
    /// wrong opens a 404.
    @Test("Pull request API URLs become /pull/ links")
    func pullRequests() {
        let link = NotificationLink.browserURL(
            fromAPI: url("https://api.github.com/repos/octo/server/pulls/482")
        )
        #expect(link?.absoluteString == "https://github.com/octo/server/pull/482")
    }

    @Test("Other subject kinds map onto their web paths", arguments: [
        ("issues/42", "issues/42"),
        ("commits/abc123", "commit/abc123"),
        ("releases/7", "releases/tag/7"),
        ("discussions/3", "discussions/3"),
    ])
    func otherKinds(apiPath: String, webPath: String) {
        let link = NotificationLink.browserURL(
            fromAPI: url("https://api.github.com/repos/octo/server/\(apiPath)")
        )
        #expect(link?.absoluteString == "https://github.com/octo/server/\(webPath)")
    }

    @Test("An unrecognised path yields no link")
    func unrecognised() {
        #expect(NotificationLink.browserURL(fromAPI: url("https://api.github.com/user")) == nil)
    }

    /// A notification with no subject should still take the user somewhere
    /// useful rather than nowhere.
    @Test("Without a subject the repository is the fallback")
    func fallback() {
        let item = NotificationItem(
            id: "1", title: "t", repository: "octo/server", avatarURL: nil,
            reason: .mention, updatedAt: .now, subjectType: "Unknown",
            latestCommentAPIURL: nil, subjectAPIURL: nil
        )
        #expect(NotificationLink.browserURL(for: item)?.absoluteString == "https://github.com/octo/server")
    }
}

@Suite("Notification subject types")
struct NotificationSubjectTypeTests {
    private func item(_ subjectType: String) -> NotificationItem {
        NotificationItem(
            id: "1", title: "t", repository: "o/r", avatarURL: nil,
            reason: .mention, updatedAt: .now, subjectType: subjectType,
            latestCommentAPIURL: nil, subjectAPIURL: nil
        )
    }

    @Test("Known types get an icon and a plural heading", arguments: [
        ("PullRequest", "arrow.triangle.pull", "Pull requests"),
        ("Issue", "smallcircle.filled.circle", "Issues"),
        ("Commit", "arrow.triangle.branch", "Commits"),
    ])
    func knownTypes(subjectType: String, symbol: String, label: String) {
        #expect(item(subjectType).symbolName == symbol)
        #expect(item(subjectType).subjectTypeLabel == label)
    }

    /// GitHub adds subject types over time; an unknown one must still group
    /// and render rather than vanishing.
    @Test("An unknown type falls back without losing its name")
    func unknownType() {
        #expect(item("SomethingNew").symbolName == "bell")
        #expect(item("SomethingNew").subjectTypeLabel == "SomethingNew")
    }
}
