import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("List visibility")
struct ListVisibilityTests {
    /// Stored as what is hidden, so a list added later shows up by itself
    /// rather than waiting for someone to find the switch.
    @Test("Everything is shown until it is switched off")
    func defaultsToShown() {
        let visibility = ListVisibility()
        for list in ["reviews", "anything-at-all", ListVisibility.mentionsKey] {
            for surface in DisplaySurface.allCases {
                #expect(visibility.isShown(list, in: surface))
            }
        }
    }

    @Test("A switch applies to one list in one place only")
    func switchesAreIndependent() {
        var visibility = ListVisibility()
        visibility.setShown(false, "issues", in: .menuBar)

        #expect(!visibility.isShown("issues", in: .menuBar))
        #expect(visibility.isShown("issues", in: .popover))
        #expect(visibility.isShown("issues", in: .window))
        #expect(visibility.isShown("reviews", in: .menuBar))
        #expect(visibility.isShownAnywhere("issues"))
    }

    /// A list nobody shows is not worth a request, which is what this
    /// answers for the refresh.
    @Test("A list switched off everywhere reports it")
    func hiddenEverywhere() {
        var visibility = ListVisibility()
        for surface in DisplaySurface.allCases {
            visibility.setShown(false, ListVisibility.mentionsKey, in: surface)
        }
        #expect(!visibility.isShownAnywhere(ListVisibility.mentionsKey))
        #expect(visibility.isShownAnywhere("reviews"))
    }

    /// A deleted list must not leave its switches behind in the settings,
    /// where a new list could inherit them by reusing the id.
    @Test("Forgetting a list clears its switches")
    func forgetting() {
        var visibility = ListVisibility()
        visibility.setShown(false, "gone", in: .menuBar)
        visibility.setShown(false, "stays", in: .menuBar)
        visibility.forget("gone")
        #expect(visibility.storedKeys == ["stays.menuBar"])
    }

    @Test("The setting survives a round trip through its stored form")
    func roundTrip() {
        var visibility = ListVisibility()
        visibility.setShown(false, "reviews", in: .window)
        visibility.setShown(false, ListVisibility.mentionsKey, in: .menuBar)

        let restored = ListVisibility(storedKeys: visibility.storedKeys)
        #expect(restored == visibility)
        #expect(!restored.isShown("reviews", in: .window))
        #expect(!restored.isShown(ListVisibility.mentionsKey, in: .menuBar))
        #expect(restored.isShown("reviews", in: .menuBar))
    }

    @Test("Switching one back on removes it from the stored form")
    func switchingBackOn() {
        var visibility = ListVisibility()
        visibility.setShown(false, "issues", in: .window)
        visibility.setShown(true, "issues", in: .window)
        #expect(visibility.storedKeys.isEmpty)
    }
}

@MainActor
@Suite("Hidden lists leave the window")
struct ListVisibilityStateTests {
    private let reviews = SavedList(
        id: "reviews", title: "Reviews", query: "is:pr review-requested:@me", content: .pullRequests
    )
    private let issues = SavedList(
        id: "issues", title: "Issues", query: "is:issue assignee:@me", content: .issues
    )

    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.settings.savedLists = [reviews, issues]
        state.listPullRequests[reviews.id] = [pullRequest(id: "1")]
        state.listIssues[issues.id] = [issue(id: "i1")]
        state.notifications = [notification(id: "n1")]
        state.sidebarSelection = .list(id: reviews.id, repository: nil)
        return state
    }

    private func pullRequest(id: String) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "a/b", author: "a", authorAvatarURL: nil,
            url: URL(string: "https://github.com")!, isDraft: false, updatedAt: .now,
            reviewDecision: .none, checks: .none
        )
    }

    private func issue(id: String) -> IssueItem {
        IssueItem(
            id: id, number: 1, title: "t", repository: "a/b", author: "a", authorAvatarURL: nil,
            url: URL(string: "https://github.com")!, updatedAt: .now
        )
    }

    private func notification(id: String) -> NotificationItem {
        NotificationItem(
            id: id, title: "t", repository: "a/b", avatarURL: nil, reason: .mention,
            updatedAt: .now, subjectType: "Issue", latestCommentAPIURL: nil, subjectAPIURL: nil
        )
    }

    private func hide(_ key: String, in surface: DisplaySurface, on state: AppState) {
        var visibility = state.settings.listVisibility
        visibility.setShown(false, key, in: surface)
        state.settings.listVisibility = visibility
        state.normaliseSelection()
    }

    /// The lists come in sidebar order, with the mentions after them.
    @Test("Each surface reports the lists it was left with")
    func countsPerSurface() {
        let state = makeState()
        hide(ListVisibility.mentionsKey, in: .menuBar, on: state)

        #expect(state.counts(in: .menuBar).map(\.id) == ["reviews", "issues"])
        #expect(state.counts(in: .window).map(\.id) == ["reviews", "issues", ListVisibility.mentionsKey])
        #expect(state.counts(in: .window).map(\.count) == [1, 1, 1])
    }

    /// The content column follows the sidebar selection, so a list hidden
    /// while it is on screen has to hand over -- otherwise it stays visible
    /// with no sidebar entry to leave it by.
    @Test("Hiding the list on screen moves the selection on")
    func selectionMovesOff() {
        let state = makeState()
        hide(reviews.id, in: .window, on: state)
        #expect(state.sidebarSelection == .list(id: issues.id, repository: nil))
    }

    @Test("A selection that is still shown is left alone")
    func selectionKept() {
        let state = makeState()
        state.sidebarSelection = .list(id: issues.id, repository: "a/b")
        hide(reviews.id, in: .window, on: state)
        #expect(state.sidebarSelection == .list(id: issues.id, repository: "a/b"))
    }

    /// With every list switched off the window still has its other views, so
    /// the selection lands on one of them rather than on nothing.
    @Test("With no list left the window falls back to the charts")
    func allHidden() {
        let state = makeState()
        for key in [reviews.id, issues.id, ListVisibility.mentionsKey] {
            hide(key, in: .window, on: state)
        }
        #expect(state.sidebarSelection == .dashboard)
        #expect(state.counts(in: .window).isEmpty)
    }

    /// A list deleted while it was on screen leaves the same hole as one
    /// switched off.
    @Test("Deleting the list on screen moves the selection on")
    func deletedList() {
        let state = makeState()
        state.settings.savedLists = [issues]
        state.normaliseSelection()
        #expect(state.sidebarSelection == .list(id: issues.id, repository: nil))
    }

    /// The window opens on the first list; if that one is switched off, the
    /// first thing shown must not be a list that is not in the sidebar.
    @Test("A fresh state never starts on a hidden list")
    func startsOnSomethingVisible() {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let settings = Settings(store: defaults)
        settings.savedLists = [reviews, issues]
        var visibility = settings.listVisibility
        visibility.setShown(false, reviews.id, in: .window)
        settings.listVisibility = visibility

        let state = AppState(settings: settings)
        #expect(state.sidebarSelection == .list(id: issues.id, repository: nil))
    }

    /// Only the lists have switches: the charts and the settings are always
    /// there.
    @Test("Views without a switch are never moved off")
    func viewsWithoutASwitch() {
        let state = makeState()
        for selection in [SidebarSelection.dashboard, .trends, .settings] {
            state.sidebarSelection = selection
            state.normaliseSelection()
            #expect(state.sidebarSelection == selection)
        }
    }
}
