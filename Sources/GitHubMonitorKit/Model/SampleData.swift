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
            additions: 195, deletions: 76, changedFiles: 6, comments: 4,
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
    /// Assembles a patch long enough to outrun the column it is read in.
    ///
    /// Written as lists of lines rather than one long string literal: a
    /// forty-line patch inside a Swift string is unreadable in the one place
    /// it has to be maintained.
    private static func longPatch(
        header: String, removed: [String], added: [String], context: [String]
    ) -> String {
        ([header]
            + removed.map { "-" + $0 }
            + added.map { "+" + $0 }
            + context.map { " " + $0 }
        ).joined(separator: "\n")
    }

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
            // Two long patches in a row, deliberately. A file taller than
            // the column is the only way to be reading the middle of one,
            // and two of them in sequence is what it takes to see where the
            // scroll lands when the first is folded away.
            ChangedFile(
                path: "src/Filter/SessionFilter.php",
                additions: 25, deletions: 7, change: .modified,
                patch: longPatch(
                    header: "@@ -12,24 +12,46 @@ class SessionFilter",
                    removed: [
                        "    public $id;",
                        "    public $data;",
                        "",
                        "    public function matches($row)",
                        "    {",
                        "        return $row['id'] == $this->id;",
                        "    }",
                    ],
                    added: [
                        "    public string $id = '';",
                        "    public string $data = '';",
                        "    private ?Clock $clock = null;",
                        "",
                        "    public function matches(array $row): bool",
                        "    {",
                        "        if (!isset($row['id'])) {",
                        "            return false;",
                        "        }",
                        "",
                        "        // Compare as strings: the column is a char(36)",
                        "        // and PHP would otherwise read '0e123' as a float.",
                        "        if ((string) $row['id'] !== $this->id) {",
                        "            return false;",
                        "        }",
                        "",
                        "        return $this->notExpired($row);",
                        "    }",
                        "",
                        "    private function notExpired(array $row): bool",
                        "    {",
                        "        $clock = $this->clock ?? new SystemClock();",
                        "",
                        "        return $row['expires_at'] > $clock->now();",
                        "    }",
                    ],
                    context: [
                        "    public function describe(): string",
                        "    {",
                        "        return sprintf('session %s', $this->id);",
                        "    }",
                        "}",
                    ]
                )
            ),
            ChangedFile(
                path: "src/Filter/UserFilter.php",
                additions: 20, deletions: 7, change: .modified,
                patch: longPatch(
                    header: "@@ -8,18 +8,38 @@ class UserFilter",
                    removed: [
                        "#[ModuleId('_system_module_id_')]",
                        "    public $login;",
                        "",
                        "    public function matches($row)",
                        "    {",
                        "        return $row['login'] == $this->login;",
                        "    }",
                    ],
                    added: [
                        "#[ModuleId(_system_module_id_)]",
                        "    public string $login = '';",
                        "    private array $teams = [];",
                        "",
                        "    public function matches(array $row): bool",
                        "    {",
                        "        if (strcasecmp($row['login'], $this->login) === 0) {",
                        "            return true;",
                        "        }",
                        "",
                        "        // A review asked of a team names the team, not",
                        "        // the person, so the teams have to be checked too.",
                        "        foreach ($this->teams as $team) {",
                        "            if (in_array($row['login'], $team->members(), true)) {",
                        "                return true;",
                        "            }",
                        "        }",
                        "",
                        "        return false;",
                        "    }",
                    ],
                    context: [
                        "    public function withTeams(array $teams): self",
                        "    {",
                        "        $copy = clone $this;",
                        "        $copy->teams = $teams;",
                        "",
                        "        return $copy;",
                        "    }",
                        "}",
                    ]
                )
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

    /// Conversations on the diff, covering the three kinds the overlay has
    /// to draw: one still open, one resolved and therefore folded away, and
    /// one GitHub can no longer place because the code it was about has
    /// since been rewritten.
    public static func reviewThreads() -> [ReviewThread] {
        [
            ReviewThread(
                id: "thread-1",
                path: "src/Filter/UserFilter.php",
                line: 14,
                side: .new,
                isResolved: false,
                isOutdated: false,
                comments: [
                    IssueComment(
                        id: "comment-1",
                        author: "arun",
                        avatarURL: avatar(2),
                        createdAt: Date().addingTimeInterval(-3 * 3600),
                        body: "`strcasecmp` on a login is right, but this will "
                            + "also match an account that was renamed. Worth a "
                            + "lookup by id instead?"
                    ),
                    IssueComment(
                        id: "comment-2",
                        author: viewer,
                        avatarURL: avatar(5),
                        createdAt: Date().addingTimeInterval(-2 * 3600),
                        body: "The id is not in the row here \u{2014} it comes from "
                            + "the search API, which only gives the login."
                    ),
                ]
            ),
            ReviewThread(
                id: "thread-2",
                path: "src/Session/SessionHandler.php",
                line: 120,
                side: .new,
                isResolved: true,
                isOutdated: false,
                comments: [
                    IssueComment(
                        id: "comment-3",
                        author: "noor",
                        avatarURL: avatar(3),
                        createdAt: Date().addingTimeInterval(-26 * 3600),
                        body: "Does the unique index cover `data` as well?"
                    ),
                    IssueComment(
                        id: "comment-4",
                        author: "mira",
                        avatarURL: avatar(1),
                        createdAt: Date().addingTimeInterval(-25 * 3600),
                        body: "Only `id`. That is the whole bug."
                    ),
                ]
            ),
            ReviewThread(
                id: "thread-3",
                path: "src/Filter/SessionFilter.php",
                line: nil,
                side: .new,
                isResolved: false,
                isOutdated: true,
                comments: [
                    IssueComment(
                        id: "comment-5",
                        author: "dara",
                        avatarURL: avatar(4),
                        createdAt: Date().addingTimeInterval(-4 * 24 * 3600),
                        body: "This compared the ids as numbers, which made "
                            + "`0e123` equal to zero. Please keep them strings."
                    )
                ]
            ),
        ]
    }

    /// A review the size of a real refactoring: forty-three files and a
    /// couple of thousand changed lines.
    ///
    /// Here rather than only in the tests because the thing it is for --
    /// whether the diff still scrolls smoothly -- cannot be measured
    /// anywhere but in the running window. `--big` opens the overlay on
    /// it.
    public static func largeDiff() -> [ChangedFile] {
        let areas = [
            "Controller/Module", "Flow/Action", "Installer/Migrations", "LifeCycle",
            "Model", "PermissionHandler", "ReportConfiguration", "Repository", "Service",
        ]
        return (0..<43).map { index in
            let area = areas[index % areas.count]
            var lines: [String] = []
            // Several hunks per file, which is what a refactoring looks
            // like and what multiplies the scrolling columns two layouts
            // need. One hunk per file hid that entirely.
            for hunk in 0..<(3 + index % 4) {
                let at = 40 + hunk * 120
                lines.append("@@ -\(at),\(6 + index % 5) +\(at),\(14 + index % 9) @@ class Handler\(index)")
                lines.append("     public function case\(hunk)(): void")
                lines.append("     {")
                for i in 0..<(4 + index % 5) {
                    lines.append("-        $this->assertSame($old[\(i)], $actual->value(\(i)));")
                }
                for i in 0..<(10 + index % 9) {
                    lines.append(
                        "+        $this->assertSame($expected[\(i)], "
                            + "$actual->total(\(i)), 'row \(i) of handler \(index)');"
                    )
                }
                lines.append("     }")
            }
            return ChangedFile(
                path: "core/module_bcm/src/\(area)/Handler\(index).php",
                additions: 40 + index % 9,
                deletions: 4 + index % 5,
                change: .modified,
                patch: lines.joined(separator: "\n")
            )
        }
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
