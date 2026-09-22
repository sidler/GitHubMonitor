import AppKit
import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("A list's searches")
struct ListQueryTests {
    private func list(_ query: String, content: ListContent = .pullRequests) -> SavedList {
        SavedList(id: "l", title: "A list", query: query, content: content)
    }

    @Test("One line is one search")
    func singleLine() {
        let searches = ListQuery.searches(
            for: list("is:pr is:open author:@me"),
            repositoryFilters: []
        )
        #expect(searches.map(\.query) == ["is:pr is:open author:@me"])
        #expect(searches.first?.listID == "l")
        #expect(searches.first?.content == .pullRequests)
    }

    /// Repeated review qualifiers are AND-ed by GitHub, so "requested from
    /// me or one of my teams" has to be two searches. Blank lines are the
    /// result of typing, not an empty search.
    @Test("Several lines are several searches, blank ones dropped")
    func severalLines() {
        let searches = ListQuery.searches(
            for: list("""
            is:pr review-requested:@me

               is:pr author:@me
            """),
            repositoryFilters: []
        )
        #expect(searches.map(\.query) == ["is:pr review-requested:@me", "is:pr author:@me"])
    }

    /// GitHub resolves team membership itself: a review requested from a
    /// team is returned by `review-requested:@me` for everyone on it. The
    /// app used to send a second search per team, which was asking twice.
    @Test("Nothing is substituted into a query")
    func noSubstitution() {
        let query = "is:pr review-requested:@me"
        let searches = ListQuery.searches(for: list(query), repositoryFilters: [])
        #expect(searches.map(\.query) == [query])
    }

    @Test("The global repository filter is appended")
    func repositoryFilter() {
        let searches = ListQuery.searches(
            for: list("is:pr author:@me"),
            repositoryFilters: ["octo", "other/thing"]
        )
        #expect(searches.map(\.query) == ["is:pr author:@me org:octo repo:other/thing"])
    }

    /// A list written for one repository should not also be narrowed to
    /// whatever the settings happen to say.
    @Test("A search that names its own scope is left alone", arguments: [
        "is:pr repo:octo/platform",
        "is:pr org:octo",
        "is:pr user:sidler",
        "is:pr -repo:octo/legacy",
    ])
    func ownScopeWins(query: String) {
        let searches = ListQuery.searches(
            for: list(query),
            repositoryFilters: ["somewhere"]
        )
        #expect(searches.map(\.query) == [query])
    }

    @Test("A word that merely contains a qualifier is not a scope")
    func lookalikes() {
        #expect(!ListQuery.namesAScope("is:pr label:repo:cleanup-ish"))
        #expect(ListQuery.namesAScope("is:pr repo:a/b"))
    }

    // MARK: - The document

    private var searches: [ListSearch] {
        [
            ListSearch(listID: "a", content: .pullRequests, query: "q1"),
            ListSearch(listID: "a", content: .pullRequests, query: "q2"),
            ListSearch(listID: "b", content: .issues, query: "q3"),
        ]
    }

    @Test("Every search becomes its own alias in one document")
    func documentAliases() {
        let document = ListQuery.document(searches)
        #expect(document.contains("s0: search("))
        #expect(document.contains("s1: search("))
        #expect(document.contains("s2: search("))
        #expect(document.contains("fragment Results"))
        #expect(document.contains("fragment IssueResults"))
    }

    /// GraphQL rejects a document that declares a fragment nothing uses.
    @Test("Only the fragments in use are declared")
    func fragmentsFollowTheContent() {
        let pullRequestsOnly = ListQuery.document([
            ListSearch(listID: "a", content: .pullRequests, query: "q"),
        ])
        #expect(pullRequestsOnly.contains("fragment Results"))
        #expect(!pullRequestsOnly.contains("IssueResults"))

        let issuesOnly = ListQuery.document([
            ListSearch(listID: "b", content: .issues, query: "q"),
        ])
        #expect(issuesOnly.contains("fragment IssueResults"))
        #expect(!issuesOnly.contains("fragment Results"))
    }

    @Test("Queries are escaped rather than pasted in")
    func escaping() {
        let document = ListQuery.document([
            ListSearch(listID: "a", content: .pullRequests, query: "is:pr \"quoted thing\""),
        ])
        #expect(document.contains("\\\"quoted thing\\\""))
    }
}

@Suite("Saved lists")
struct SavedListTests {
    @Test("A list needs a title and at least one search to run")
    func runnable() {
        #expect(SavedList(title: "A", query: "is:pr", content: .pullRequests).isRunnable)
        #expect(!SavedList(title: "A", query: "  \n ", content: .pullRequests).isRunnable)
        #expect(!SavedList(title: "", query: "is:pr", content: .pullRequests).isRunnable)
    }

    @Test("A list falls back to its content's symbol")
    func symbol() {
        #expect(SavedList(title: "A", query: "q", content: .issues).symbol == StatusBarTitleBuilder.issueSymbol)
        #expect(
            SavedList(title: "A", query: "q", content: .issues, symbolName: "star").symbol == "star"
        )
    }

    /// Only issues carry a type, so only an issue list can be ordered or
    /// split by one.
    @Test("What a list can be ordered and grouped by follows its content")
    func optionsFollowContent() {
        #expect(!ListContent.pullRequests.sorts.contains(.type))
        #expect(ListContent.issues.sorts.contains(.type))
        #expect(!ListContent.pullRequests.groupings.contains(.byType))
        #expect(ListContent.issues.groupings.contains(.byType))
    }

    /// The seeds are what the app used to hard-code; the ids are fixed so
    /// settings written before lists existed still find them.
    @Test("The seeded lists reproduce what the app started with")
    func seeds() throws {
        let seeds = SavedList.seeds(grouping: .byRepository, issueSettings: (.flat, .type, ["Bug"]))
        #expect(seeds.map(\.id) == [SavedList.Seed.reviews, SavedList.Seed.authored, SavedList.Seed.issues])

        let reviews = try #require(seeds.first)
        #expect(reviews.content == .pullRequests)
        #expect(reviews.grouping == .byRepository)
        // One search: GitHub's `review-requested:` already covers the teams
        // one is on, so a second line asking for them would ask twice.
        #expect(reviews.queryLines == ["is:pr is:open archived:false review-requested:@me"])

        let issues = try #require(seeds.last)
        #expect(issues.content == .issues)
        #expect(issues.sort == .type)
        #expect(issues.hiddenTypes == ["Bug"])
    }

    @Test("Lists survive the round trip through their stored form")
    func codable() throws {
        let lists = SavedList.seeds(grouping: .flat, issueSettings: (.byType, .created, ["Task"]))
        let restored = try #require(Settings.decode(Settings.encode(lists)))
        #expect(restored == lists)
    }
}

@MainActor
@Suite("Lists on first launch")
struct ListMigrationTests {
    private func store() -> UserDefaults {
        UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
    }

    @Test("A fresh install starts with the three lists the app had")
    func seeded() {
        let lists = Settings(store: store()).savedLists
        #expect(lists.map(\.title) == ["Reviews Requested", "My Pull Requests", "My Issues"])
        #expect(lists.map(\.content) == [.pullRequests, .pullRequests, .issues])
    }

    /// The settings written before lists were editable are keyed by the same
    /// ids the seeds carry, so a menu bar someone had switched off stays off
    /// and the orders they chose stay chosen.
    @Test("What was configured before carries over to the seeded lists")
    func carriesOldSettingsOver() throws {
        let defaults = store()
        defaults.set(ListGrouping.byRepository.rawValue, forKey: "listGrouping")
        defaults.set(ListGrouping.byType.rawValue, forKey: "issueGrouping")
        defaults.set(ListSort.type.rawValue, forKey: "issueSort")
        defaults.set(["Bug"], forKey: "hiddenIssueTypes")
        defaults.set(["issues.menuBar"], forKey: "hiddenLists")

        let settings = Settings(store: defaults)
        let reviews = try #require(settings.list(withID: SavedList.Seed.reviews))
        let issues = try #require(settings.list(withID: SavedList.Seed.issues))

        #expect(reviews.grouping == .byRepository)
        #expect(issues.grouping == .byType)
        #expect(issues.sort == .type)
        #expect(issues.hiddenTypes == ["Bug"])
        // The switch was stored under the same key the seeded list uses.
        #expect(!settings.listVisibility.isShown(issues.id, in: .menuBar))
        #expect(settings.listVisibility.isShown(issues.id, in: .window))
    }

    /// Seeding once is the point: a list deleted on purpose must not come
    /// back at the next launch.
    @Test("Lists are seeded once, not restored")
    func seededOnce() {
        let defaults = store()
        let settings = Settings(store: defaults)
        settings.savedLists = [
            SavedList(id: "only", title: "Only", query: "is:pr", content: .pullRequests),
        ]

        #expect(Settings(store: defaults).savedLists.map(\.id) == ["only"])
    }

    /// An empty set of lists is a choice too, and reseeding would undo it.
    @Test("Deleting every list leaves it deleted")
    func emptyStaysEmpty() {
        let defaults = store()
        let settings = Settings(store: defaults)
        settings.savedLists = []
        #expect(Settings(store: defaults).savedLists.isEmpty)
    }
}

@Suite("Presets")
struct ListPresetTests {
    /// What a new account gets is the same thing anyone can add later, so
    /// the seeds have to be presets rather than a second kind of list.
    @Test("A fresh install is seeded from presets, keeping their ids")
    func seedsComeFromPresets() {
        let seeds = SavedList.seeds(grouping: .flat, issueSettings: (.flat, .updated, []))
        #expect(seeds.map(\.id) == ListPresets.seeded.map(\.id))
        #expect(seeds.map(\.title) == ListPresets.seeded.map(\.title))
    }

    /// "Ready to merge" is a way of working, not a fact about an account:
    /// offered in the menu, never added on somebody's behalf.
    @Test("Ready to merge is offered but not seeded")
    func readyToMergeIsOptional() {
        #expect(ListPresets.all.contains(ListPresets.readyToMerge))
        #expect(!ListPresets.seeded.contains(ListPresets.readyToMerge))
    }

    /// Approved, green, not a draft -- and about the user, since a search
    /// for every approved pull request on GitHub would be a list of
    /// strangers' work.
    @Test("Ready to merge asks for what its name says")
    func readyToMergeQuery() {
        let query = ListPresets.readyToMerge.query
        #expect(query.contains("review:approved"))
        #expect(query.contains("status:success"))
        #expect(query.contains("-is:draft"))
        #expect(query.contains("involves:@me"))
        #expect(ListPresets.readyToMerge.content == .pullRequests)
    }

    /// Adding the same preset twice must produce two lists, not two lists
    /// fighting over one id.
    @Test("A preset added later gets an id of its own")
    func addedPresetsGetFreshIDs() {
        let first = ListPresets.readyToMerge.list()
        let second = ListPresets.readyToMerge.list()
        #expect(first.id != second.id)
        #expect(first.id != ListPresets.readyToMerge.id)
        #expect(first.query == second.query)
    }

    @Test("Every preset is runnable as it stands")
    func presetsAreRunnable() {
        for preset in ListPresets.all {
            let list = preset.list()
            #expect(list.isRunnable)
            #expect(!preset.summary.isEmpty)
            // The searches have to match what the list says it shows.
            for line in list.queryLines {
                switch preset.content {
                case .pullRequests: #expect(line.contains("is:pr"))
                case .issues: #expect(line.contains("is:issue"))
                }
            }
        }
    }

    /// An icon that the system does not know would be an empty gap in the
    /// sidebar, the popover and the menu bar at once.
    @Test("Every offered symbol exists on this system")
    func symbolsExist() {
        for name in SavedList.symbolChoices + ListPresets.all.compactMap(\.symbolName) {
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "unknown symbol \(name)"
            )
        }
    }
}

@MainActor
@Suite("The team placeholder, after it was retired")
struct TeamPlaceholderMigrationTests {
    /// Lists stored while the app expanded `@myteams` still carry that line.
    /// Nothing expands it now, and a placeholder left in a search is a
    /// search that can only fail -- so it goes, and the line beside it
    /// already covers what it asked for.
    @Test("The line is dropped from stored lists")
    func dropsTheLine() throws {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let stored = [
            SavedList(
                id: "reviews", title: "Reviews Requested",
                query: """
                is:pr is:open archived:false review-requested:@me
                is:pr is:open archived:false team-review-requested:@myteams
                """,
                content: .pullRequests
            ),
        ]
        defaults.set(Settings.encode(stored), forKey: "savedLists")

        let list = try #require(Settings(store: defaults).savedLists.first)
        #expect(list.queryLines == ["is:pr is:open archived:false review-requested:@me"])
    }

    /// A list that never used it must come back exactly as it was.
    @Test("Everything else is left alone")
    func leavesOthersAlone() throws {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let stored = [
            SavedList(id: "a", title: "A", query: "is:pr author:@me", content: .pullRequests),
        ]
        defaults.set(Settings.encode(stored), forKey: "savedLists")
        #expect(Settings(store: defaults).savedLists == stored)
    }
}
