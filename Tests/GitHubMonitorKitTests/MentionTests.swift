import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("Reading an @ out of half-written prose")
struct MentionTypingTests {
    @Test("A bare @ is a question with no letters in it yet")
    func justTyped() {
        #expect(MentionTyping.query(in: "thanks @") == "")
        #expect(MentionTyping.query(in: "@") == "")
    }

    @Test("What follows the @ is what is being asked")
    func partial() {
        #expect(MentionTyping.query(in: "ask @mi") == "mi")
        #expect(MentionTyping.query(in: "@mira") == "mira")
        #expect(MentionTyping.query(in: "line one\nand @no") == "no")
    }

    /// An address is the case this has to get right: nobody writing
    /// "stefan.idler@artemeon.de" is asking to be offered a list of
    /// colleagues, and GitHub does not read it as a mention either.
    @Test("An @ inside a word is an address, not a mention")
    func insideAWord() {
        #expect(MentionTyping.query(in: "mail stefan@artemeon") == nil)
        #expect(MentionTyping.query(in: "a@b") == nil)
    }

    @Test("A finished name is not still being typed")
    func finished() {
        #expect(MentionTyping.query(in: "@mira please look") == nil)
        #expect(MentionTyping.query(in: "@mira,") == nil)
        #expect(MentionTyping.query(in: "nothing here") == nil)
    }

    /// The last one, because that is the one being written. The ones
    /// before it are already settled.
    @Test("The one being typed is the last one")
    func theLastOne() {
        #expect(MentionTyping.query(in: "@mira and @no") == "no")
    }

    /// The caret is what this gained when the box became an NSTextView.
    /// A name being fixed in the middle of a paragraph used to be
    /// invisible, because only the end of the text was ever read.
    @Test("The mention is the one in front of the caret, not the last one in the text")
    func atTheCaret() {
        let text = "ask @mi about the @other thing"
        let caret = MentionTyping.index(ofUTF16: 7, in: text)   // after "@mi"
        #expect(MentionTyping.query(in: text, before: caret) == "mi")
    }

    @Test("Nothing in front of the caret is nothing to complete")
    func notAtTheCaret() {
        let text = "ask @mira about it"
        #expect(
            MentionTyping.query(in: text, before: MentionTyping.index(ofUTF16: 3, in: text))
                == nil
        )
    }

    @Test("Completing at the caret keeps what came after it, and says where to go")
    func completesInTheMiddle() {
        let text = "ask @mi about it"
        let caret = MentionTyping.index(ofUTF16: 7, in: text)
        let done = MentionTyping.completing(text, with: "mira", before: caret)
        // One space, not two: the sentence already had one.
        #expect(done.text == "ask @mira about it")
        #expect(done.caret == 9)
    }

    /// An offset that does not fit the string is not a reason to trap:
    /// the selection and the text arrive from different places and can
    /// disagree for one pass.
    @Test("A caret past the end is treated as the end")
    func caretOutOfRange() {
        #expect(MentionTyping.index(ofUTF16: 99, in: "short") == "short".endIndex)
        #expect(MentionTyping.index(ofUTF16: -1, in: "short") == "short".endIndex)
    }

    @Test("Completing replaces what was typed and leaves room for the rest")
    func completes() {
        #expect(MentionTyping.completing("ask @mi", with: "mira") == "ask @mira ")
        #expect(MentionTyping.completing("@", with: "noor") == "@noor ")
        #expect(
            MentionTyping.completing("@mira and @no", with: "noor") == "@mira and @noor "
        )
    }

    @Test("Completing something that is not a mention changes nothing")
    func completesNothing() {
        #expect(MentionTyping.completing("no mention", with: "mira") == "no mention")
        #expect(MentionTyping.completing("a@b", with: "mira") == "a@b")
    }
}

@Suite("Choosing whom to offer")
struct MentionMatchTests {
    private let people = [
        MentionableUser(login: "roman", name: "Roman Vogel"),
        MentionableUser(login: "annika", name: "Annika Roth"),
        MentionableUser(login: "mira", name: "Mira Hollanda"),
        MentionableUser(login: "susanne", name: nil),
    ]

    @Test("Nothing typed offers whoever is there")
    func everybody() {
        #expect(MentionQuery.matches("", in: people).count == 4)
    }

    /// The ordering is the point. "an" is in "roman" and "susanne" too,
    /// and somebody typing it means annika.
    @Test("A login that starts with what was typed comes first")
    func prefixWins() {
        #expect(MentionQuery.matches("an", in: people).first?.login == "annika")
    }

    @Test("A real name is matched as well as a login")
    func byName() {
        #expect(MentionQuery.matches("hollanda", in: people).map(\.login) == ["mira"])
    }

    @Test("Case is not something anybody should have to get right")
    func caseless() {
        #expect(MentionQuery.matches("MIR", in: people).map(\.login) == ["mira"])
    }

    @Test("Nobody matching is an empty list, not everybody")
    func nobody() {
        #expect(MentionQuery.matches("zzz", in: people).isEmpty)
    }

    @Test("The list stops at what fits under the box")
    func capped() {
        let many = (1...20).map { MentionableUser(login: "person\($0)") }
        #expect(MentionQuery.matches("person", in: many).count == MentionQuery.shown)
        #expect(MentionQuery.matches("", in: many).count == MentionQuery.shown)
    }
}

@Suite("When GitHub is worth asking again")
struct MentionNarrowingTests {
    private func catalogue(_ logins: [String], total: Int) -> MentionQuery.Catalogue {
        MentionQuery.Catalogue(users: logins.map { MentionableUser(login: $0) }, total: total)
    }

    @Test("A page that is the whole list answers for itself")
    func complete() {
        let whole = catalogue(["mira", "noor"], total: 2)
        #expect(whole.isComplete)
        // Nobody called "zzz" here means nobody called "zzz" at all.
        #expect(!MentionQuery.needsNarrowing("zzz", in: whole))
    }

    @Test("A page with the name in it needs no second question")
    func found() {
        let part = catalogue(["mira", "noor"], total: 400)
        #expect(!MentionQuery.needsNarrowing("mir", in: part))
    }

    @Test("A page that is only part of the list, and holds nobody matching, does")
    func missing() {
        let part = catalogue(["mira", "noor"], total: 400)
        #expect(MentionQuery.needsNarrowing("annika", in: part))
    }

    @Test("With nothing typed there is nothing to narrow to")
    func nothingTyped() {
        #expect(!MentionQuery.needsNarrowing("", in: catalogue(["mira"], total: 400)))
    }
}

@Suite("Asking GitHub who may be mentioned")
struct MentionServiceTests {
    @Test("Logins, names and pictures are parsed; a node without a login is not a person")
    func parses() throws {
        let catalogue = try MentionQuery.catalogue(from: [
            "repository": [
                "mentionableUsers": [
                    "totalCount": 9,
                    "nodes": [
                        [
                            "login": "mira",
                            "name": "Mira Hollanda",
                            "avatarUrl": "https://avatars.githubusercontent.com/u/1?v=4",
                        ],
                        // No name is a real answer: plenty of accounts
                        // have none, and an empty one is the same thing
                        // said differently.
                        ["login": "noor", "name": ""],
                        ["name": "nobody at all"],
                    ],
                ]
            ]
        ])

        #expect(catalogue.users.map(\.login) == ["mira", "noor"])
        #expect(catalogue.users.first?.name == "Mira Hollanda")
        #expect(catalogue.users.first?.avatarURL != nil)
        #expect(catalogue.users.last?.name == nil)
        #expect(!catalogue.isComplete)
    }

    @Test("Something that is not a repository is an error, not an empty list")
    func refusesNonsense() {
        #expect(throws: GitHubError.self) {
            _ = try MentionQuery.catalogue(from: ["repository": NSNull()])
        }
    }

    @Test("A name that is not owner/name never leaves the house")
    func refusesHalfARepository() async {
        let stub = StubGitHub.answering([StubGitHub.Answer()])
        let service = GitHubService(token: "token", session: stub.session)

        await #expect(throws: GitHubError.self) {
            _ = try await service.mentionableUsers(inRepository: "server")
        }
        #expect(stub.sent.isEmpty)
    }

    @Test("What comes back is what the editor offers")
    func reads() async throws {
        let stub = StubGitHub.answering([
            StubGitHub.Answer(
                body: try JSONSerialization.data(withJSONObject: [
                    "data": [
                        "repository": [
                            "mentionableUsers": [
                                "totalCount": 1,
                                "nodes": [["login": "mira", "name": "Mira Hollanda"]],
                            ]
                        ]
                    ]
                ])
            )
        ])

        let catalogue = try await GitHubService(token: "token", session: stub.session)
            .mentionableUsers(inRepository: "octo/server", matching: "mi")

        #expect(catalogue.users.map(\.login) == ["mira"])
        #expect(stub.sent.count == 1)
    }
}
