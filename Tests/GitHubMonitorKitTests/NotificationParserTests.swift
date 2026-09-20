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
        #expect(NotificationParser.commentBody(from: Data(#"{"body":"hello"}"#.utf8)) == "hello")
        // Commit notifications carry "message" instead of "body".
        #expect(NotificationParser.commentBody(from: Data(#"{"message":"fix: thing"}"#.utf8)) == "fix: thing")
    }

    /// An empty body must read as "no preview", not as an empty bubble.
    @Test("Blank comment bodies count as no body")
    func blankBody() {
        #expect(NotificationParser.commentBody(from: Data(#"{"body":""}"#.utf8)) == nil)
        #expect(NotificationParser.commentBody(from: Data(#"{"body":"   \n "}"#.utf8)) == nil)
        #expect(NotificationParser.commentBody(from: Data(#"{}"#.utf8)) == nil)
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
