import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Pull request detail")
struct PullRequestDetailQueryTests {
    private func payload(
        checks: [[String: Any]] = [],
        reviews: [[String: Any]] = [],
        requests: [[String: Any]] = [],
        mergeable: String = "MERGEABLE",
        body: String? = "Adds the export button."
    ) -> [String: Any] {
        [
            "node": [
                "headRefName": "feature/csv-export",
                "baseRefName": "main",
                "additions": 120,
                "deletions": 45,
                "changedFiles": 7,
                "comments": ["totalCount": 3],
                "body": body as Any,
                "mergeable": mergeable,
                "commits": ["nodes": [["commit": [
                    "statusCheckRollup": ["contexts": ["nodes": checks]],
                ]]]],
                "latestReviews": ["nodes": reviews],
                "reviewRequests": ["nodes": requests],
            ],
        ]
    }

    private func checkRun(_ name: String, conclusion: String?, status: String = "COMPLETED") -> [String: Any] {
        var node: [String: Any] = ["name": name, "status": status]
        if let conclusion { node["conclusion"] = conclusion }
        return node
    }

    @Test("Change counts are read across")
    func counts() throws {
        let detail = try PullRequestDetailQuery.detail(from: payload())
        #expect(detail.additions == 120)
        #expect(detail.deletions == 45)
        #expect(detail.changedFiles == 7)
        #expect(detail.comments == 3)
    }

    /// Asked again here rather than carried over from the row: by the time
    /// a pane is opened GitHub has usually finished working it out.
    @Test("The pane reads the merge state for itself")
    func mergeStatus() throws {
        #expect(try PullRequestDetailQuery.detail(from: payload()).mergeStatus == .mergeable)
        #expect(
            try PullRequestDetailQuery.detail(from: payload(mergeable: "CONFLICTING"))
                .mergeStatus == .conflicting
        )
        #expect(
            try PullRequestDetailQuery.detail(from: payload(mergeable: "UNKNOWN"))
                .mergeStatus == .unknown
        )
    }

    @Test("Branch names are read across")
    func branches() throws {
        let detail = try PullRequestDetailQuery.detail(from: payload())
        #expect(detail.headBranch == "feature/csv-export")
        #expect(detail.baseBranch == "main")
    }

    /// A plain field on the pull request, so the pane pays nothing extra
    /// for it -- but it has to be asked for to arrive.
    @Test("The description is asked for and read across")
    func body() throws {
        #expect(PullRequestDetailQuery.document.contains("body"))
        #expect(try PullRequestDetailQuery.detail(from: payload()).body == "Adds the export button.")
    }

    @Test("A pull request opened without a description reads as empty")
    func missingBody() throws {
        #expect(try PullRequestDetailQuery.detail(from: payload(body: nil)).body.isEmpty)
    }

    @Test("A missing node is an error, not an empty detail")
    func missingNode() {
        #expect(throws: GitHubError.self) {
            try PullRequestDetailQuery.detail(from: [:])
        }
    }

    @Test("Check conclusions map onto the model", arguments: [
        ("SUCCESS", ChecksStatus.success),
        ("FAILURE", ChecksStatus.failure),
        ("TIMED_OUT", ChecksStatus.failure),
        // Cancelled and skipped runs are not failures; reporting them as such
        // would send the reviewer chasing a problem that is not there.
        ("CANCELLED", ChecksStatus.none),
        ("SKIPPED", ChecksStatus.none),
        ("NEUTRAL", ChecksStatus.none),
    ])
    func conclusions(raw: String, expected: ChecksStatus) throws {
        let detail = try PullRequestDetailQuery.detail(
            from: payload(checks: [checkRun("build", conclusion: raw)])
        )
        #expect(detail.checks.first?.status == expected)
    }

    /// A run still in flight has no conclusion yet and must not read as a pass.
    @Test("An unfinished run counts as running")
    func inFlight() throws {
        let detail = try PullRequestDetailQuery.detail(
            from: payload(checks: [checkRun("build", conclusion: nil, status: "IN_PROGRESS")])
        )
        #expect(detail.checks.first?.status == .pending)
    }

    @Test("Legacy status contexts are read too")
    func statusContexts() throws {
        let detail = try PullRequestDetailQuery.detail(
            from: payload(checks: [["context": "ci/jenkins", "state": "FAILURE"]])
        )
        #expect(detail.checks.map(\.name) == ["ci/jenkins"])
        #expect(detail.checks.first?.status == .failure)
    }

    /// Failures are the reason to open this pane, so they go first.
    @Test("Checks are ordered failing, running, passing")
    func checkOrder() throws {
        let detail = try PullRequestDetailQuery.detail(from: payload(checks: [
            checkRun("pass", conclusion: "SUCCESS"),
            checkRun("run", conclusion: nil, status: "IN_PROGRESS"),
            checkRun("fail", conclusion: "FAILURE"),
        ]))
        #expect(detail.checks.map(\.name) == ["fail", "run", "pass"])
        #expect(detail.failingChecks.count == 1)
        #expect(detail.passingChecks.count == 1)
        #expect(detail.runningChecks.count == 1)
    }

    @Test("Reviews and outstanding requests are merged")
    func reviewers() throws {
        let detail = try PullRequestDetailQuery.detail(from: payload(
            reviews: [["state": "APPROVED", "author": ["login": "mira", "avatarUrl": "https://e/a.png"]]],
            requests: [["requestedReviewer": ["login": "sidler", "avatarUrl": "https://e/b.png"]]]
        ))
        #expect(detail.reviewers.count == 2)
        #expect(detail.reviewers.first { $0.name == "mira" }?.state == .approved)
        #expect(detail.reviewers.first { $0.name == "sidler" }?.state == .pending)
    }

    /// Someone who reviewed and was then asked again appears in both lists;
    /// the review they actually left is the more useful state.
    @Test("A re-requested reviewer keeps their review state")
    func reRequestedReviewer() throws {
        let detail = try PullRequestDetailQuery.detail(from: payload(
            reviews: [["state": "CHANGES_REQUESTED", "author": ["login": "mira"]]],
            requests: [["requestedReviewer": ["login": "mira"]]]
        ))
        #expect(detail.reviewers.count == 1)
        #expect(detail.reviewers.first?.state == .changesRequested)
    }

    @Test("Teams are listed as reviewers too")
    func teamReviewer() throws {
        let detail = try PullRequestDetailQuery.detail(from: payload(
            requests: [["requestedReviewer": ["name": "backend"]]]
        ))
        #expect(detail.reviewers.first?.name == "backend")
        #expect(detail.reviewers.first?.isTeam == true)
        #expect(detail.reviewers.first?.state == .pending)
    }

    /// A user and a team could share a name; their entries must stay separate.
    @Test("A team and a user with the same name are distinct")
    func teamAndUserCollision() throws {
        let detail = try PullRequestDetailQuery.detail(from: payload(
            reviews: [["state": "APPROVED", "author": ["login": "core"]]],
            requests: [["requestedReviewer": ["name": "core"]]]
        ))
        #expect(detail.reviewers.count == 2)
    }

    @Test("Reviewers are ordered by what needs attention")
    func reviewerOrder() throws {
        let detail = try PullRequestDetailQuery.detail(from: payload(
            reviews: [
                ["state": "APPROVED", "author": ["login": "approver"]],
                ["state": "CHANGES_REQUESTED", "author": ["login": "blocker"]],
            ],
            requests: [["requestedReviewer": ["login": "waiting"]]]
        ))
        #expect(detail.reviewers.map(\.name) == ["blocker", "waiting", "approver"])
    }

    @Test("A pull request without checks or reviewers still parses")
    func empty() throws {
        let detail = try PullRequestDetailQuery.detail(from: ["node": [:]])
        #expect(detail.checks.isEmpty)
        #expect(detail.reviewers.isEmpty)
        #expect(detail.changedFiles == 0)
        // Empty rather than absent, so the view can simply skip the row.
        #expect(detail.headBranch.isEmpty)
    }
}

/// The line shown next to the fold, so a closed description still says
/// what it is about.
@Suite("The folded description")
struct DescriptionSummaryTests {
    private let title = DescriptionSection.title

    @Test("The first line with words on it is the hint")
    func firstLine() {
        #expect(DescriptionSection.firstLine(of: "\n\nFixes the race.\nMore below.", besides: title) == "Fixes the race.")
    }

    /// Heading and quote marks are punctuation for a renderer; read aloud
    /// they are noise.
    @Test("Leading marks are dropped")
    func marks() {
        #expect(DescriptionSection.firstLine(of: "## What this fixes\n\ntext", besides: title) == "What this fixes")
        #expect(DescriptionSection.firstLine(of: "> quoted", besides: title) == "quoted")
    }

    /// The house template opens with `## Description`, and the hint sat
    /// next to a label of the same word.
    @Test("A first line that repeats the section's name is skipped")
    func repeatsTheTitle() {
        #expect(
            DescriptionSection.firstLine(of: "## Description\n\nCloses #1", besides: title)
                == "Closes #1"
        )
    }

    @Test("A description of nothing but blank lines has no hint")
    func blank() {
        #expect(DescriptionSection.firstLine(of: "\n   \n", besides: title) == nil)
    }
}
