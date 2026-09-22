import Foundation

/// A list somebody might want, ready to be added.
///
/// The three the app starts with are presets too: what a new account gets on
/// first launch is the same thing anyone can add later, rather than a second
/// kind of list that happens to exist from the start.
public struct ListPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// One line in the menu, saying what the search actually asks for.
    public let summary: String
    public let query: String
    public let content: ListContent
    public let symbolName: String?

    public init(
        id: String,
        title: String,
        summary: String,
        query: String,
        content: ListContent,
        symbolName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.query = query
        self.content = content
        self.symbolName = symbolName
    }

    /// Builds the list.
    ///
    /// A fresh id unless one is given: the seeded lists keep the preset's id
    /// so settings made before lists were editable still find them, while a
    /// preset added later is a new list -- adding the same one twice must
    /// not produce two lists fighting over one id.
    public func list(
        id: String? = nil,
        grouping: ListGrouping = .flat,
        sort: ListSort = .updated,
        hiddenTypes: Set<String> = []
    ) -> SavedList {
        SavedList(
            id: id ?? UUID().uuidString,
            title: title,
            query: query,
            content: content,
            symbolName: symbolName,
            grouping: grouping,
            sort: sort,
            hiddenTypes: hiddenTypes
        )
    }
}

public enum ListPresets {
    public static let reviews = ListPreset(
        id: SavedList.Seed.reviews,
        title: "Reviews Requested",
        summary: "Open pull requests waiting for your review, or one of your teams'",
        // One search: `review-requested:` covers the teams you are on.
        // GitHub's own words: "If the requested person is on a team that is
        // requested for review, then review requests for that team will also
        // appear in the search results." Asking for both was asking twice.
        query: "is:pr is:open archived:false review-requested:@me",
        content: .pullRequests
    )

    public static let authored = ListPreset(
        id: SavedList.Seed.authored,
        title: "My Pull Requests",
        summary: "What you opened and are waiting on other people for",
        query: "is:pr is:open archived:false author:@me",
        content: .pullRequests,
        symbolName: "person.crop.circle"
    )

    public static let issues = ListPreset(
        id: SavedList.Seed.issues,
        title: "My Issues",
        summary: "Open issues assigned to you",
        query: "is:issue is:open archived:false assignee:@me",
        content: .issues
    )

    /// Approved, green, and not a draft -- the ones nothing is stopping any
    /// more.
    ///
    /// Scoped by `involves:@me` rather than by a repository: a search for
    /// every approved pull request on GitHub would be a list of strangers'
    /// work, and the repository to narrow it to is not something a preset
    /// can know. Narrowing it to one is a `repo:` away.
    public static let readyToMerge = ListPreset(
        id: "ready-to-merge",
        title: "Ready to merge",
        summary: "Approved, checks passing, not a draft — and you are on it",
        query: "is:pr is:open archived:false involves:@me review:approved status:success -is:draft",
        content: .pullRequests,
        symbolName: "checkmark.seal"
    )

    /// Everything a new list can start from.
    public static let all: [ListPreset] = [reviews, authored, issues, readyToMerge]

    /// What a fresh install starts with: the lists the app used to have
    /// hard-coded, and nothing else. "Ready to merge" is offered, not
    /// imposed -- it is a way of working, not a fact about the account.
    public static let seeded: [ListPreset] = [reviews, authored, issues]
}
