import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("The conversation behind a notification")
struct ThreadQueryTests {
    /// The notifications API hands out REST URLs; GraphQL wants the pieces.
    @Test("The subject URL is taken apart", arguments: [
        ("https://api.github.com/repos/octo/platform/issues/35442", "octo", "platform", 35442),
        ("https://api.github.com/repos/octo/platform/pulls/7", "octo", "platform", 7),
    ])
    func subject(url: String, owner: String, name: String, number: Int) throws {
        let subject = try #require(ThreadQuery.subject(from: URL(string: url)!))
        #expect(subject.owner == owner)
        #expect(subject.name == name)
        #expect(subject.number == number)
    }

    /// Commits and releases have no conversation, and their URLs say so by
    /// not looking like one.
    @Test("Anything else is refused rather than guessed at", arguments: [
        "https://api.github.com/repos/octo/platform/commits/abc123",
        "https://api.github.com/repos/octo/platform",
        "https://api.github.com/notifications",
    ])
    func notAConversation(url: String) {
        #expect(ThreadQuery.subject(from: URL(string: url)!) == nil)
    }

    /// One document serves both kinds: by the time a notification arrives,
    /// nothing in it says whether the subject is an issue or a pull request.
    @Test("The document asks for both kinds")
    func document() {
        #expect(ThreadQuery.document.contains("issueOrPullRequest"))
        #expect(ThreadQuery.document.contains("... on Issue"))
        #expect(ThreadQuery.document.contains("... on PullRequest"))
    }

    @Test("The description and the end of the thread are read")
    func parsing() throws {
        let thread = try ThreadQuery.thread(from: [
            "repository": [
                "issueOrPullRequest": [
                    "body": "The **description**.",
                    "comments": [
                        "totalCount": 6,
                        "nodes": [
                            [
                                "id": "C_1",
                                "createdAt": "2026-09-03T09:23:02Z",
                                "body": "First",
                                "author": ["login": "faltavilla", "avatarUrl": "https://example.com/a.png"],
                            ],
                            [
                                "id": "C_2",
                                "createdAt": "2026-09-10T12:07:06Z",
                                "body": "@avery please look",
                                "author": ["login": "mrick808"],
                            ],
                        ],
                    ],
                ],
            ],
        ])

        #expect(thread.body.contains("**description**"))
        #expect(thread.comments.map(\.author) == ["faltavilla", "mrick808"])
        #expect(thread.totalComments == 6)
        // The pane says how much of the thread it is not showing.
        #expect(thread.olderComments == 4)
    }

    @Test("A subject that is neither is an error, not an empty pane")
    func missingSubject() {
        #expect(throws: GitHubError.self) {
            try ThreadQuery.thread(from: ["repository": ["issueOrPullRequest": NSNull()]])
        }
    }
}

@Suite("Finding the mention in a thread")
struct MentionMatchingTests {
    private func comment(_ body: String) -> IssueComment {
        IssueComment(id: "c", author: "a", avatarURL: nil, createdAt: .now, body: body)
    }

    @Test("A comment that names you is marked")
    func names() {
        #expect(comment("cc @avery please review").mentions("avery"))
        #expect(comment("@avery").mentions("avery"))
        #expect(comment("ping @Avery, thanks").mentions("avery"))
    }

    /// `@sid` must not match `@avery`, and a name inside another word is
    /// not a mention either.
    @Test("A longer name is not a match")
    func doesNotOverreach() {
        #expect(!comment("cc @averyberg").mentions("avery"))
        #expect(!comment("cc @avery-bot").mentions("avery"))
        #expect(!comment("no mention at all").mentions("avery"))
        #expect(!comment("avery without the at sign").mentions("avery"))
    }

    @Test("Without a login nothing is marked")
    func noViewer() {
        #expect(!comment("@avery").mentions(""))
    }
}
