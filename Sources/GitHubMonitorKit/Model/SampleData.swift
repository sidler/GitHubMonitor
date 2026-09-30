import Foundation

/// Made-up content: what the app shows when it is launched with `--sample`
/// and nobody has a token, and what tests reach for when they need a row
/// that looks like a real one rather than four invented fields.
///
/// Everything here is fiction. The repositories and people do not exist,
/// which is the point: the app is developed against private repositories,
/// and screenshots and fixtures made from those would carry work that is
/// not ours to publish.
public enum SampleData {
    public static let viewer = "avery"

    public enum Repository {
        public static let platform = "octo/platform"
        public static let server = "octo/server"
        public static let toolkit = "octo/toolkit"
        public static let website = "octo/website"
    }

    /// Avatars are asked of GitHub's own placeholder ids, so a run without
    /// a token still draws faces rather than grey circles.
    static func avatar(_ id: Int) -> URL? {
        URL(string: "https://avatars.githubusercontent.com/u/\(id)?v=4")
    }

    static func url(_ repository: String, _ number: Int) -> URL {
        URL(string: "https://github.com/\(repository)/pull/\(number)")!
    }

    static func ago(hours: Double) -> Date { .now.addingTimeInterval(-3600 * hours) }
    static func ago(days: Double) -> Date { .now.addingTimeInterval(-86400 * days) }

    // MARK: - Pull requests

    /// The queue of reviews asked of this person: one of everything a row
    /// can say, so no state of the row is only ever seen against the real
    /// API.
    public static func reviewsRequested() -> [PullRequestItem] {
        [
            PullRequestItem(
                id: "pr-482", number: 482,
                title: "Fix race condition in session handler",
                repository: Repository.server, author: "mira", authorAvatarURL: avatar(1),
                url: url(Repository.server, 482), isDraft: false,
                createdAt: ago(days: 11), updatedAt: ago(hours: 1),
                reviewDecision: .reviewRequired, checks: .success,
                mergeStatus: .conflicting,
                headCommit: "22da5a177503201b9cbbe78802da6353299f74df",
                isAutoMergeArmed: true,
                // Long enough to be called overdue under any sane threshold.
                reviewRequestedAt: ago(days: 9),
                reviews: ReviewTally(accepted: 0, declined: 0, pending: 2),
                links: [
                    ItemLink(
                        reference: ItemReference(repository: Repository.server, number: 318),
                        kind: .closes,
                        title: "Session table migration order is ambiguous",
                        url: url(Repository.server, 318)
                    ),
                ],
                linkedTotal: 2
            ),
            PullRequestItem(
                id: "pr-77", number: 77,
                title: "Add a formatting ruleset to CI",
                repository: Repository.toolkit, author: "arun", authorAvatarURL: avatar(2),
                url: url(Repository.toolkit, 77), isDraft: true,
                createdAt: ago(days: 4), updatedAt: ago(days: 3),
                reviewDecision: .changesRequested, checks: .failure,
                mergeStatus: .mergeable,
                reviews: ReviewTally(accepted: 0, declined: 1, pending: 1)
            ),
            PullRequestItem(
                id: "pr-1204", number: 1204,
                title: "Bump dependencies for the new runtime",
                repository: Repository.toolkit, author: "dara", authorAvatarURL: avatar(3),
                url: url(Repository.toolkit, 1204), isDraft: false,
                createdAt: ago(days: 1), updatedAt: ago(hours: 0.2),
                reviewDecision: .reviewRequired, checks: .pending,
                mergeStatus: .mergeable,
                reviewRequestedAt: ago(days: 4),
                reviews: ReviewTally(accepted: 1, declined: 0, pending: 1)
            ),
            PullRequestItem(
                id: "pr-903", number: 903,
                title: "#611 Cache the rendered navigation between requests",
                repository: Repository.platform, author: "noor", authorAvatarURL: avatar(4),
                url: url(Repository.platform, 903), isDraft: false,
                createdAt: ago(days: 6), updatedAt: ago(hours: 5),
                reviewDecision: .approved, checks: .success,
                mergeStatus: .mergeable,
                reviewRequestedAt: ago(days: 2),
                reviews: ReviewTally(accepted: 2, declined: 0, pending: 0),
                links: [
                    ItemLink(
                        reference: ItemReference(repository: Repository.platform, number: 611),
                        kind: .closes,
                        title: "Navigation is rebuilt on every request",
                        url: url(Repository.platform, 611)
                    ),
                ]
            ),
            PullRequestItem(
                id: "pr-905", number: 905,
                title: "Drop the legacy importer",
                repository: Repository.platform, author: "mira", authorAvatarURL: avatar(1),
                url: url(Repository.platform, 905), isDraft: false,
                createdAt: ago(days: 2), updatedAt: ago(hours: 20),
                reviewDecision: .none, checks: .none,
                mergeStatus: .mergeable,
                reviewRequestedAt: ago(hours: 20),
                reviews: ReviewTally(accepted: 0, declined: 0, pending: 3)
            ),
            PullRequestItem(
                id: "pr-118", number: 118,
                title: "Document the release checklist",
                repository: Repository.website, author: "arun", authorAvatarURL: avatar(2),
                url: url(Repository.website, 118), isDraft: false,
                createdAt: ago(days: 18), updatedAt: ago(days: 8),
                reviewDecision: .reviewRequired, checks: .success,
                mergeStatus: .mergeable,
                reviewRequestedAt: ago(days: 5),
                reviews: ReviewTally(accepted: 0, declined: 0, pending: 1)
            ),
        ]
    }

    /// This person's own work, so the pane that refuses to approve has
    /// something to refuse.
    public static func myPullRequests() -> [PullRequestItem] {
        [
            PullRequestItem(
                id: "pr-909", number: 909,
                title: "#615 Split the settings pane into tabs",
                repository: Repository.platform, author: viewer, authorAvatarURL: avatar(5),
                url: url(Repository.platform, 909), isDraft: false,
                createdAt: ago(days: 3), updatedAt: ago(hours: 3),
                reviewDecision: .reviewRequired, checks: .success,
                mergeStatus: .mergeable,
                viewerDidAuthor: true,
                reviews: ReviewTally(accepted: 1, declined: 0, pending: 2),
                links: [
                    ItemLink(
                        reference: ItemReference(repository: Repository.platform, number: 615),
                        kind: .closes,
                        title: "Settings has outgrown one pane",
                        url: url(Repository.platform, 615)
                    ),
                ]
            ),
            PullRequestItem(
                id: "pr-912", number: 912,
                title: "Retire the old chart colours",
                repository: Repository.platform, author: viewer, authorAvatarURL: avatar(5),
                url: url(Repository.platform, 912), isDraft: true,
                createdAt: ago(days: 1), updatedAt: ago(hours: 9),
                reviewDecision: .none, checks: .pending,
                mergeStatus: .mergeable,
                viewerDidAuthor: true
            ),
        ]
    }

    // MARK: - Issues

    public static func issues() -> [IssueItem] {
        [
            IssueItem(
                id: "i-318", number: 318,
                title: "Session table migration order is ambiguous",
                repository: Repository.server, author: "mira", authorAvatarURL: avatar(1),
                url: url(Repository.server, 318),
                createdAt: ago(days: 9), updatedAt: ago(hours: 1.5),
                comments: 7,
                labels: [
                    IssueLabel(name: "bug", color: "d73a4a"),
                    IssueLabel(name: "needs decision", color: "fbca04"),
                ],
                milestone: "8.3",
                type: IssueType(name: "Bug", color: .red),
                links: [
                    ItemLink(
                        reference: ItemReference(repository: Repository.server, number: 482),
                        kind: .closes,
                        title: "Fix race condition in session handler",
                        url: url(Repository.server, 482)
                    ),
                ]
            ),
            IssueItem(
                id: "i-611", number: 611,
                title: "Navigation is rebuilt on every request",
                repository: Repository.platform, author: "noor", authorAvatarURL: avatar(4),
                url: url(Repository.platform, 611),
                createdAt: ago(days: 21), updatedAt: ago(hours: 6),
                comments: 3,
                labels: [IssueLabel(name: "performance", color: "0e8a16")],
                type: IssueType(name: "Task", color: .blue),
                links: [
                    ItemLink(
                        reference: ItemReference(repository: Repository.platform, number: 903),
                        kind: .closes,
                        title: "#611 Cache the rendered navigation between requests",
                        url: url(Repository.platform, 903)
                    ),
                ]
            ),
            IssueItem(
                id: "i-615", number: 615,
                title: "Settings has outgrown one pane",
                repository: Repository.platform, author: viewer, authorAvatarURL: avatar(5),
                url: url(Repository.platform, 615),
                createdAt: ago(days: 30), updatedAt: ago(days: 3),
                comments: 1,
                labels: [IssueLabel(name: "design", color: "c5def5")],
                type: IssueType(name: "Feature", color: .purple)
            ),
            IssueItem(
                id: "i-91", number: 91,
                title: "Write down how a release is cut",
                repository: Repository.website, author: "arun", authorAvatarURL: avatar(2),
                url: url(Repository.website, 91),
                createdAt: ago(days: 30), updatedAt: ago(days: 2),
                labels: [IssueLabel(name: "documentation", color: "0075ca")]
            ),
            IssueItem(
                id: "i-94", number: 94,
                title: "Search returns nothing for hyphenated terms",
                repository: Repository.website, author: "dara", authorAvatarURL: avatar(3),
                url: url(Repository.website, 94),
                createdAt: ago(days: 5), updatedAt: ago(hours: 30),
                comments: 12,
                labels: [
                    IssueLabel(name: "bug", color: "d73a4a"),
                    IssueLabel(name: "good first issue", color: "7057ff"),
                ],
                type: IssueType(name: "Bug", color: .red)
            ),
        ]
    }

    // MARK: - What one pull request is made of

    /// The description behind `pr-482`, written the way real ones are: a
    /// heading, a table, a checklist and numbers in prose, so the Markdown
    /// and the link reading are both exercised.
    public static let description = """
    ## What this fixes

    Two requests arriving together both wrote a session row, and
    the unique index added in 8.3 turned the second one into a
    fatal error.

    | Case | Before | After |
    | --- | --- | --- |
    | New session | insert | insert |
    | Known session | insert, fails | update |

    - [x] Covered by `SessionHandlerTest`
    - [ ] Needs the migration to have run
    - Ticked and plain in one list, which is what GitHub does

    Related to #4712, and blocked by #9999 until that is decided.
    """

    public static func detail() -> PullRequestDetail {
        PullRequestDetail(
            headBranch: "fix/session-handler-race",
            baseBranch: "main",
            additions: 154, deletions: 64, changedFiles: 6, comments: 4,
            body: description,
            mergeStatus: .conflicting,
            checks: [
                CheckRun(name: "unit tests", status: .success),
                CheckRun(name: "static analysis", status: .success),
            ],
            reviewers: [
                ReviewerStatus(name: "arun", avatarURL: avatar(2), state: .pending, isTeam: false),
            ]
        )
    }

    /// One small patch, one large enough to stay folded, and a tree deep
    /// enough for the file index to have something to collapse.
    public static func changedFiles() -> [ChangedFile] {
        [
            ChangedFile(
                path: "src/Session/SessionHandler.php",
                additions: 6, deletions: 2, change: .modified,
                patch: """
                @@ -118,8 +118,12 @@ class SessionHandler implements SessionHandlerInterface
                     public function write(string $id, string $data): bool
                     {
                -        $this->connection->insert(self::TABLE, ['id' => $id]);
                -        return true;
                +        // The unique index fails on rows written before 8.3.
                +        if ($this->connection->has(self::TABLE, $id)) {
                +            return $this->connection->update(self::TABLE, ['data' => $data]);
                +        }
                +
                +        return $this->connection->insert(self::TABLE, ['id' => $id, 'data' => $data]);
                     }
                """
            ),
            ChangedFile(
                path: "src/Session/migrations.yml",
                additions: 2, deletions: 0, change: .modified,
                patch: "@@ -4,2 +4,4 @@\n order:\n   - Migration20260901120000\n+  - Migration20260901123000\n+  # runs after the column exists\n"
            ),
            ChangedFile(
                path: "src/Filter/SessionFilter.php",
                additions: 3, deletions: 1, change: .modified,
                patch: "@@ -12,3 +12,5 @@\n class SessionFilter\n-    public $id;\n+    public string $id = '';\n+    public string $data = '';\n"
            ),
            ChangedFile(
                path: "src/Filter/UserFilter.php",
                additions: 1, deletions: 1, change: .modified,
                patch: "@@ -8,1 +8,1 @@\n-#[ModuleId('_system_module_id_')]\n+#[ModuleId(_system_module_id_)]\n"
            ),
            ChangedFile(
                path: "README.md",
                additions: 2, deletions: 0, change: .modified,
                patch: "@@ -1,2 +1,4 @@\n # Platform\n+\n+Requires the 8.4 runtime.\n"
            ),
            ChangedFile(
                path: "tests/Session/SessionHandlerTest.php",
                additions: 140, deletions: 60, change: .modified,
                patch: "@@ -1,200 +1,280 @@\n"
                    + Array(repeating: "+        $this->assertTrue(true);", count: 40)
                        .joined(separator: "\n")
            ),
        ]
    }

    /// One file ticked off, one changed since it was ticked, and the rest
    /// untouched -- all three states the diff has to draw.
    public static func viewedFiles() -> [String: FileViewedState] {
        [
            "src/Session/migrations.yml": .viewed,
            "src/Filter/UserFilter.php": .dismissed,
        ]
    }

    // MARK: - Linked items

    /// Two looked-up links and one number that turned out to be nothing, so
    /// both sides of the panel are exercised: what a summary looks like,
    /// and that a wrong guess draws nothing at all.
    public static func linkedSummaries() -> [String: LinkedSummaryState] {
        [
            "\(Repository.server)#318": .loaded(
                LinkedSummary(
                    reference: ItemReference(repository: Repository.server, number: 318),
                    kind: .issue,
                    state: .open,
                    title: "Session table migration order is ambiguous",
                    author: "mira",
                    authorAvatarURL: avatar(1),
                    url: url(Repository.server, 318),
                    createdAt: ago(days: 9),
                    updatedAt: ago(hours: 1.5),
                    body: """
                    The two migrations can run in either order, and one of them
                    assumes the other has already added the column.

                    We need to decide whether the order is declared or derived.
                    """,
                    comments: 7,
                    labels: [
                        IssueLabel(name: "bug", color: "d73a4a"),
                        IssueLabel(name: "needs decision", color: "fbca04"),
                    ]
                )
            ),
            "\(Repository.server)#4712": .loaded(
                LinkedSummary(
                    reference: ItemReference(repository: Repository.server, number: 4712),
                    kind: .pullRequest,
                    state: .merged,
                    title: "Introduce the migration registry",
                    author: "arun",
                    authorAvatarURL: avatar(2),
                    url: url(Repository.server, 4712),
                    createdAt: ago(days: 40),
                    updatedAt: ago(days: 20),
                    body: "Groundwork this one builds on.",
                    comments: 2,
                    checks: .success,
                    reviewDecision: .approved,
                    changedFiles: 14, additions: 220, deletions: 31
                )
            ),
            "\(Repository.server)#9999": .missing,
        ]
    }
}
