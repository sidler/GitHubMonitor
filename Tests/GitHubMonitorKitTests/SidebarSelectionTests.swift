import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Sidebar selection")
struct SidebarSelectionTests {
    @Test("An 'All' selection is titled by its section")
    func sectionTitles() {
        #expect(SidebarSelection.pullRequests(repository: nil).title == "Reviews Requested")
        #expect(SidebarSelection.mentions(repository: nil).title == "Mentions")
        #expect(SidebarSelection.pullRequests(repository: nil).subtitle == nil)
    }

    /// With a repository chosen, its name is the headline and the section
    /// moves to the subtitle -- otherwise the header would not say what kind
    /// of list is on screen.
    @Test("A repository selection keeps the section as a subtitle")
    func repositoryTitles() {
        let selection = SidebarSelection.pullRequests(repository: "octo/platform")
        #expect(selection.title == "octo/platform")
        #expect(selection.subtitle == "Reviews Requested")
    }

    /// The two pull request lists must be distinguishable at a glance;
    /// naming both "Pull Requests" would make the header useless.
    @Test("The two pull request lists have distinct titles")
    func distinctPullRequestTitles() {
        #expect(SidebarSelection.myPullRequests(repository: nil).title == "My Pull Requests")
        #expect(
            SidebarSelection.pullRequests(repository: nil).title
                != SidebarSelection.myPullRequests(repository: nil).title
        )
        #expect(SidebarSelection.myPullRequests(repository: "a/b") != .pullRequests(repository: "a/b"))
    }

    @Test("Selections map onto the right list")
    func tabs() {
        #expect(SidebarSelection.pullRequests(repository: "a/b").tab == .pullRequests)
        #expect(SidebarSelection.mentions(repository: nil).tab == .mentions)
        #expect(SidebarSelection.settings.tab == .settings)
    }

    /// Selections are used as list tags, so two entries that look alike must
    /// not compare equal.
    @Test("Selections for different repositories are distinct")
    func distinctTags() {
        #expect(SidebarSelection.pullRequests(repository: "a/b") != .pullRequests(repository: "a/c"))
        #expect(SidebarSelection.pullRequests(repository: "a/b") != .mentions(repository: "a/b"))
        #expect(SidebarSelection.pullRequests(repository: nil) != .pullRequests(repository: "a/b"))
    }
}

@MainActor
@Suite("Selection narrows the lists")
struct AppStateSelectionTests {
    private func makeState() -> AppState {
        // An isolated defaults suite, so tests never touch the real settings.
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.pullRequests = [
            pullRequest(id: "1", repository: "octo/platform"),
            pullRequest(id: "2", repository: "octo/platform"),
            pullRequest(id: "3", repository: "octo/octo.de"),
        ]
        state.notifications = [
            notification(id: "n1", repository: "octo/platform"),
        ]
        return state
    }

    private func pullRequest(id: String, repository: String) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: repository, author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
    }

    private func notification(id: String, repository: String) -> NotificationItem {
        NotificationItem(
            id: id, title: "t", repository: repository, avatarURL: nil,
            reason: .mention, updatedAt: .now, subjectType: "Issue",
            latestCommentAPIURL: nil, subjectAPIURL: nil
        )
    }

    @Test("'All' shows everything")
    func allShowsEverything() {
        let state = makeState()
        state.sidebarSelection = .pullRequests(repository: nil)
        #expect(state.selectedPullRequests.count == 3)
    }

    @Test("A repository selection narrows the list")
    func repositoryNarrows() {
        let state = makeState()
        state.sidebarSelection = .pullRequests(repository: "octo/platform")
        #expect(state.selectedPullRequests.map(\.id) == ["1", "2"])
    }

    /// The sidebar entries are what the user clicks, so their counts have to
    /// match what the list then shows.
    @Test("Sidebar counts match the narrowed lists")
    func countsMatchLists() {
        let state = makeState()
        for entry in state.pullRequestRepositories {
            state.sidebarSelection = .pullRequests(repository: entry.repository)
            #expect(state.selectedPullRequests.count == entry.count)
        }
    }

    @Test("Repository entries are listed busiest first")
    func busiestFirst() {
        let state = makeState()
        #expect(state.pullRequestRepositories.map(\.repository) == ["octo/platform", "octo/octo.de"])
        #expect(state.pullRequestRepositories.first?.count == 2)
    }

    @Test("Mentions narrow independently of pull requests")
    func mentionsNarrow() {
        let state = makeState()
        state.sidebarSelection = .mentions(repository: "octo/platform")
        #expect(state.selectedNotifications.count == 1)
        // A repository with no mentions yields an empty list, not everything.
        state.sidebarSelection = .mentions(repository: "octo/octo.de")
        #expect(state.selectedNotifications.isEmpty)
    }
}
