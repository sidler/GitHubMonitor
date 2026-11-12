import Foundation
import Testing

@testable import GitHubMonitorKit

/// Asking somebody else to review, and who may be asked.
@Suite("Asking for a review")
struct ReviewerPickerTests {
    private func candidate(_ login: String) -> ReviewerCandidate {
        ReviewerCandidate(id: "u-\(login)", login: login, name: nil, avatarURL: nil)
    }

    private var everybody: [ReviewerCandidate] {
        ["ada", "bob", "cat", "dan"].map(candidate)
    }

    // MARK: What the request actually does

    /// The one thing on this page that could do real harm.
    ///
    /// `requestReviews` without `union` sets the reviewer list to exactly
    /// what it is handed. Adding one person by naming one person would
    /// then withdraw the request from everybody else on the pull request
    /// -- silently, with the only sign being colleagues wondering where
    /// their review went.
    @Test("Asking one person adds to the others rather than replacing them")
    func unionIsOn() {
        let document = ReviewerQuery.requestDocument

        #expect(document.contains("union: true"))
        #expect(document.contains("requestReviews"))
        #expect(document.contains("union: false") == false)
    }

    /// Taking one back names the one, and goes to the endpoint that takes
    /// logins -- GraphQL has no mutation for withdrawing a single
    /// request, only the same whole-list replacement.
    @Test("Taking a request back names a pull request and a repository")
    func withdrawal() {
        let url = ReviewerQuery.withdrawalURL(repository: "octo/server", number: 482)

        #expect(
            url?.absoluteString
                == "https://api.github.com/repos/octo/server/pulls/482/requested_reviewers"
        )
        #expect(ReviewerQuery.withdrawalURL(repository: "nonsense", number: 1) == nil)
    }

    /// Long enough to catch a wrong name, short enough not to read as a
    /// second step of the asking.
    @Test("The way back is offered for a few seconds, not none and not forever")
    func undoWindow() {
        #expect(ReviewerQuery.undoWindow >= 5)
        #expect(ReviewerQuery.undoWindow <= 30)
    }

    // MARK: Who is offered

    @Test("Somebody already asked is not offered again")
    func alreadyAsked() {
        let offered = ReviewerQuery.offerable(
            everybody, asked: ["bob"], author: nil, viewer: nil
        )

        #expect(offered.map(\.login) == ["ada", "cat", "dan"])
    }

    /// GitHub refuses a review request from somebody on their own pull
    /// request, so an entry for the author is an entry that always fails.
    @Test("The author is not offered their own pull request")
    func author() {
        let offered = ReviewerQuery.offerable(
            everybody, asked: [], author: "cat", viewer: nil
        )

        #expect(offered.contains { $0.login == "cat" } == false)
        #expect(offered.count == 3)
    }

    @Test("You are not offered yourself")
    func viewer() {
        let offered = ReviewerQuery.offerable(
            everybody, asked: [], author: nil, viewer: "dan"
        )

        #expect(offered.contains { $0.login == "dan" } == false)
    }

    /// GitHub is not consistent about the case of a login between one
    /// endpoint and another, and a comparison that is would offer
    /// somebody who has already been asked.
    @Test("Matching a name ignores its case")
    func caseInsensitive() {
        let offered = ReviewerQuery.offerable(
            [candidate("Ada"), candidate("Bob")],
            asked: ["ada"],
            author: "BOB",
            viewer: nil
        )

        #expect(offered.isEmpty)
    }

    @Test("With nobody ruled out, everybody is offered")
    func nobodyRuledOut() {
        #expect(
            ReviewerQuery.offerable(everybody, asked: [], author: nil, viewer: nil).count == 4
        )
    }

    // MARK: What is asked of GitHub

    /// An empty filter must not travel as an empty string: GitHub reads
    /// that as a search for nothing and answers with nobody, where no
    /// filter at all means everybody.
    @Test("An empty filter is left out rather than sent empty")
    func emptyFilter() {
        let variables = ReviewerQuery.variables(
            for: ReviewerListing(repository: "octo/server", query: "")
        )

        #expect(variables?["owner"] as? String == "octo")
        #expect(variables?["name"] as? String == "server")
        #expect(variables?["query"] == nil)
    }

    @Test("A filter that was typed is sent")
    func filter() {
        let variables = ReviewerQuery.variables(
            for: ReviewerListing(repository: "octo/server", query: "kae")
        )

        #expect(variables?["query"] as? String == "kae")
        #expect(variables?["first"] as? Int == ReviewerQuery.pageSize)
    }

    @Test("Something that is not a repository is not a question")
    func badRepository() {
        #expect(ReviewerQuery.variables(for: ReviewerListing(repository: "x", query: "")) == nil)
    }

    // MARK: Reading the answer

    @Test("The people come back with their names and their ids")
    func reading() throws {
        let payload: [String: Any] = [
            "repository": [
                "collaborators": [
                    "totalCount": 27,
                    "nodes": [
                        [
                            "id": "MDQ6VXNlcjE=",
                            "login": "christiankaemper",
                            "name": "Christian Kämper",
                            "avatarUrl": "https://example.com/a.png",
                        ],
                        // No name set, which is ordinary.
                        ["id": "MDQ6VXNlcjI=", "login": "sidler", "name": NSNull()],
                        // Nothing to go on: dropped rather than guessed at.
                        ["login": "nameless"],
                    ],
                ]
            ]
        ]

        let catalogue = try ReviewerQuery.catalogue(from: payload)

        #expect(catalogue.candidates.count == 2)
        #expect(catalogue.candidates.first?.name == "Christian Kämper")
        #expect(catalogue.candidates.first?.avatarURL != nil)
        #expect(catalogue.candidates.last?.name == nil)
        // Two of twenty-seven read, so the picker has to say so.
        #expect(catalogue.total == 27)
        #expect(catalogue.isComplete == false)
    }

    /// An empty name is not a name. GitHub hands back "" for an account
    /// that never filled one in, and a blank second line under the login
    /// is a row that looks broken.
    @Test("An empty name counts as no name")
    func emptyName() {
        let found = ReviewerQuery.candidate(from: ["id": "x", "login": "ada", "name": "  "])

        #expect(found?.name == nil)
    }

    @Test("A repository answering with nothing is an error, not an empty list")
    func missingRepository() {
        #expect(throws: GitHubError.self) {
            _ = try ReviewerQuery.catalogue(from: [:])
        }
    }
}
