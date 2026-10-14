import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("Reading a repository's labels")
struct LabelCatalogueTests {
    @Test("Name, colour and the id the mutations need")
    func parses() throws {
        let payload: [String: Any] = [
            "repository": [
                "labels": [
                    "totalCount": 2,
                    "nodes": [
                        ["id": "LA_1", "name": "bug", "color": "d73a4a"],
                        ["id": "LA_2", "name": "needs decision", "color": "fbca04"],
                    ],
                ]
            ]
        ]
        let catalogue = try LabelQuery.catalogue(from: payload)

        #expect(catalogue.labels.map(\.name) == ["bug", "needs decision"])
        #expect(catalogue.labels.map(\.id) == ["LA_1", "LA_2"])
        #expect(catalogue.isComplete)
    }

    /// A repository with four hundred labels answers with sixty. The
    /// picker has to say so, or somebody concludes theirs was deleted.
    @Test("It knows when it is showing only part of the list")
    func incomplete() throws {
        let payload: [String: Any] = [
            "repository": [
                "labels": [
                    "totalCount": 400,
                    "nodes": [["id": "LA_1", "name": "bug", "color": "d73a4a"]],
                ]
            ]
        ]
        #expect(try !LabelQuery.catalogue(from: payload).isComplete)
    }

    @Test("A label with no id is left out: it could never be sent back")
    func skipsIdless() throws {
        let payload: [String: Any] = [
            "repository": [
                "labels": [
                    "totalCount": 2,
                    "nodes": [
                        ["name": "bug", "color": "d73a4a"],
                        ["id": "LA_2", "name": "docs", "color": "0075ca"],
                    ],
                ]
            ]
        ]
        #expect(try LabelQuery.catalogue(from: payload).labels.map(\.id) == ["LA_2"])
    }

    @Test("A repository that answered with nothing is an error, not an empty list")
    func missing() {
        #expect(throws: GitHubError.self) {
            try LabelQuery.catalogue(from: ["repository": NSNull()])
        }
    }

    /// Two mutations rather than one that sets the whole set: setting the
    /// set would quietly undo whatever somebody else added while the pane
    /// was open.
    @Test("Putting one on and taking one off are separate asks")
    func documents() {
        #expect(LabelQuery.addDocument.contains("addLabelsToLabelable"))
        #expect(LabelQuery.removeDocument.contains("removeLabelsFromLabelable"))
        #expect(LabelQuery.addDocument.contains("labelIds: $labels"))
        #expect(LabelQuery.removeDocument.contains("labelIds: $labels"))
        #expect(!LabelQuery.addDocument.contains("clearLabels"))
    }

    @Test("The catalogue is asked of a repository by owner and name")
    func queryShape() {
        #expect(LabelQuery.document.contains("repository(owner: $owner, name: $name)"))
        // GitHub does the narrowing. Holding every label of every
        // repository to search here would be a lot of somebody else's
        // taxonomy in memory for a field that is usually empty.
        #expect(LabelQuery.document.contains("query: $query"))
    }
}

@Suite("Asking GitHub for the labels")
struct LabelServiceTests {
    private func service(_ stub: StubGitHub.Stub) -> GitHubService {
        GitHubService(token: "token", session: stub.session)
    }

    private func answer(_ payload: [String: Any]) throws -> StubGitHub.Answer {
        StubGitHub.Answer(body: try JSONSerialization.data(withJSONObject: ["data": payload]))
    }

    @Test("What comes back is parsed into the catalogue")
    func reads() async throws {
        let stub = StubGitHub.answering([
            try answer([
                "repository": [
                    "labels": [
                        "totalCount": 1,
                        "nodes": [["id": "LA_1", "name": "bug", "color": "d73a4a"]],
                    ]
                ]
            ])
        ])

        let catalogue = try await service(stub).labels(inRepository: "octo/server")

        #expect(catalogue.labels.map(\.name) == ["bug"])
        #expect(stub.sent.count == 1)
    }

    @Test("A name that is not owner/name never leaves the house")
    func refusesNonsense() async {
        let stub = StubGitHub.answering([StubGitHub.Answer()])
        let service = service(stub)

        await #expect(throws: GitHubError.self) {
            _ = try await service.labels(inRepository: "server")
        }
        #expect(stub.sent.isEmpty)
    }

    @Test("Setting and clearing are each one request")
    func sets() async throws {
        let stub = StubGitHub.answering([try answer([:]), try answer([:])])
        let service = service(stub)

        try await service.setLabel("LA_1", on: "PR_1", to: true)
        try await service.setLabel("LA_1", on: "PR_1", to: false)

        #expect(stub.sent.count == 2)
    }
}

@Suite("Showing a label change before GitHub has agreed")
struct LabelOptimismTests {
    private let bug = IssueLabel(id: "LA_1", name: "bug", color: "d73a4a")

    private var detail: PullRequestDetail {
        PullRequestDetail(
            headBranch: "a", baseBranch: "main",
            additions: 1, deletions: 0, changedFiles: 1, comments: 0,
            checks: [], reviewers: [], labels: [bug]
        )
    }

    @Test("A pull request's detail can be handed a different set")
    func pullRequest() {
        let without = detail.withLabels([])
        #expect(without.labels.isEmpty)
        // Everything else is the detail that was already read: the pane
        // must not blink back to a spinner because a label was pressed.
        #expect(without.headBranch == detail.headBranch)
        #expect(without.additions == detail.additions)
    }

    @Test("An issue's detail too, keeping its body and its comments")
    func issue() {
        let comment = IssueComment(
            id: "c", author: "mira", avatarURL: nil, createdAt: .now, body: "text"
        )
        let detail = IssueDetail(body: "text", comments: [comment], totalComments: 1)
        let with = detail.withLabels([bug])

        #expect(with.labels.map(\.id) == ["LA_1"])
        #expect(with.body == "text")
        #expect(with.comments.count == 1)
        #expect(with.totalComments == 1)
    }

    /// A label with no id was never GitHub's. Sending it would be refused,
    /// and showing it as set in the meantime would be a lie with a delay
    /// on it.
    @Test("One without an id is not something to send")
    func idless() {
        #expect(!IssueLabel(name: "bug", color: "d73a4a").isReal)
        #expect(bug.isReal)
    }
}

/// Where the picker puts the ones already carried.
@Suite("The order the picker offers labels in")
struct LabelOrderTests {
    private func label(_ id: String, _ name: String) -> IssueLabel {
        IssueLabel(id: id, name: name, color: "cccccc")
    }

    private var catalogue: [IssueLabel] {
        [
            label("LA_1", "Aareal"),
            label("LA_2", "BCM"),
            label("LA_3", "Screening"),
            label("LA_4", "api"),
            label("LA_5", "Feature"),
        ]
    }

    /// The point of it: a repository with a hundred and seventy labels
    /// shows sixty, so the three an item carries were as likely as not
    /// off the bottom -- and taking one off is the one thing the picker
    /// is certain to be asked.
    @Test("The ones already carried come first")
    func carriedFirst() {
        let order = LabelQuery.ordered(
            catalogue, carrying: [label("LA_3", "Screening"), label("LA_5", "Feature")]
        )
        #expect(order.prefix(2).map(\.name) == ["Feature", "Screening"])
    }

    @Test("Alphabetical within each group, and case is not a sort order")
    func alphabetical() {
        let order = LabelQuery.ordered(catalogue, carrying: [])
        #expect(order.map(\.name) == ["Aareal", "api", "BCM", "Feature", "Screening"])
    }

    @Test("Carrying nothing leaves the list as the repository gave it, sorted")
    func nothingCarried() {
        #expect(LabelQuery.ordered([], carrying: []).isEmpty)
    }

    @Test("A label carried but not in this page of the list does not appear twice")
    func carriedButAbsent() {
        let order = LabelQuery.ordered(catalogue, carrying: [label("LA_99", "elsewhere")])
        #expect(order.count == catalogue.count)
        #expect(!order.contains { $0.name == "elsewhere" })
    }
}

/// What happens when a picture's address sends the client somewhere else,
/// which is what every attachment on a private repository does.
@Suite("Following a picture to where it is really kept")
struct ImageRedirectTests {
    private let github = URL(string: "https://github.com/user-attachments/assets/abc")!

    private func request(_ address: String) -> URLRequest {
        var request = URLRequest(url: URL(string: address)!)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The token goes no further than GitHub. Another host is somebody
    /// else's, and Amazon refuses a signed address carrying an
    /// Authorization header in any case -- two authorities where it
    /// expects one.
    @Test("The token is not carried to another host")
    func dropsTheToken() {
        let next = GitHubClient.following(
            request("https://github-production-user-asset.s3.amazonaws.com/a.png"), from: github
        )
        #expect(next.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A redirect that stays on GitHub keeps it")
    func keepsItAtHome() {
        let next = GitHubClient.following(
            request("https://github.com/somewhere/else"), from: github
        )
        #expect(next.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    /// GitHub answers with the address HTML-escaped, so every parameter
    /// after the first arrives named `amp;X-Amz-Something` and the
    /// signature covers a request nobody made.
    @Test("The escaped ampersands are put back")
    func unescapes() {
        let next = GitHubClient.following(
            request("https://s3.example.com/a.png?X-Amz-Date=1&amp;X-Amz-Signature=2"),
            from: github
        )
        let address = next.url?.absoluteString ?? ""
        #expect(address.contains("&X-Amz-Signature=2"))
        #expect(!address.contains("amp;"))
    }

    @Test("An address with nothing wrong with it is passed on unchanged")
    func leavesItAlone() {
        let plain = "https://s3.example.com/a.png?one=1&two=2"
        let next = GitHubClient.following(request(plain), from: github)
        #expect(next.url?.absoluteString == plain)
    }
}
