import Foundation

/// The OAuth scopes a classic token carries, as reported by GitHub's
/// `X-OAuth-Scopes` response header.
public struct TokenScopes: Equatable, Sendable {
    public let granted: Set<String>

    public init(granted: Set<String>) {
        self.granted = granted
    }

    public init(header: String?) {
        guard let header else {
            granted = []
            return
        }
        granted = Set(
            header
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    /// What this app needs, and why, for the settings screen to explain
    /// itself.
    ///
    /// `repo` is written as what it is. GitHub's classic scope has no
    /// read-only half: it grants write across every repository the account
    /// can reach.
    ///
    /// The list of writes is part of the promise, so it has to be kept.
    /// It said "exactly one thing: the approval you confirm in the diff"
    /// for several releases after the app had learnt to merge, to label
    /// and to resolve -- a sentence that was true when it was written and
    /// a misstatement by the time anybody read it. **Anything added that
    /// writes to GitHub belongs here**: the mutations live in
    /// `ApprovalQuery`, `MergeQuery`, `LabelQuery`, `ReviewThreadsQuery`
    /// and `ViewedFilesQuery` -- and `ProjectQuery`, which writes under
    /// its own scope rather than under `repo`.
    public static let required: [(scope: String, purpose: String)] = [
        (
            "repo",
            "full access to repositories, including private ones; GitHub's classic "
                + "scope has no read-only half. The app reads pull requests and issues, "
                + "and writes what you ask it to: remarks and replies on a diff, a "
                + "review (approve, request changes or comment), resolving a "
                + "conversation, labels, viewed ticks, and merging a pull request."
        ),
        ("notifications", "read notifications and mark them read"),
    ]

    /// Worth having, and not worth refusing a token over. Without it the
    /// app simply does not ask GitHub about boards; with it a linked
    /// ticket says which board it is on and which column of it.
    public static let optional: [(scope: String, purpose: String)] = [
        ("read:project", "name the boards a linked issue or pull request sits on"),
        // Standing on its own, not as a continuation of the line above:
        // the settings screen lists these one per row, each with its own
        // tick, and a sentence beginning "and" read as a fragment there.
        ("read:org", "name the column it is in on those boards"),
        (
            "project",
            "move an issue to another column from its pane. GitHub's project scope "
                + "has no read-only half either: it grants full control of every "
                + "board the account can reach"
        ),
    ]

    /// Every scope the app knows about, required ones first.
    ///
    /// The settings screen walks this rather than the two lists: what
    /// somebody asks of that screen is "which of these do I have", and
    /// that question does not sort by whether the app insists.
    public static let catalogue: [(scope: String, purpose: String, isRequired: Bool)] =
        required.map { ($0.scope, $0.purpose, true) }
        + optional.map { ($0.scope, $0.purpose, false) }

    /// Scopes that imply others. GitHub lists only the broadest scope granted,
    /// so `admin:org` alone must satisfy a `read:org` requirement.
    private static let implications: [String: Set<String>] = [
        "admin:org": ["write:org", "read:org"],
        "write:org": ["read:org"],
        "repo": ["repo:status", "repo_deployment", "public_repo", "repo:invite", "security_events"],
        "admin:repo_hook": ["write:repo_hook", "read:repo_hook"],
        "write:repo_hook": ["read:repo_hook"],
        "user": ["read:user", "user:email", "user:follow"],
        "project": ["read:project"],
    ]

    /// Everything the token grants, including what the granted scopes imply.
    public var effective: Set<String> {
        var result = granted
        for scope in granted {
            result.formUnion(Self.implications[scope] ?? [])
        }
        return result
    }

    public func has(_ scope: String) -> Bool {
        effective.contains(scope)
    }

    /// Required scopes the token does not cover, in the order they are listed.
    public var missing: [String] {
        Self.required.map(\.scope).filter { !has($0) }
    }

    public var isComplete: Bool {
        missing.isEmpty
    }
}
