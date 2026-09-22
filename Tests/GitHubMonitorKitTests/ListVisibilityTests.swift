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
        for list in WatchedList.allCases {
            for surface in DisplaySurface.allCases {
                #expect(visibility.isShown(list, in: surface))
            }
        }
    }

    @Test("A switch applies to one list in one place only")
    func switchesAreIndependent() {
        var visibility = ListVisibility()
        visibility.setShown(false, .issues, in: .menuBar)

        #expect(!visibility.isShown(.issues, in: .menuBar))
        #expect(visibility.isShown(.issues, in: .popover))
        #expect(visibility.isShown(.issues, in: .window))
        #expect(visibility.isShown(.reviews, in: .menuBar))
        #expect(visibility.isShownAnywhere(.issues))
    }

    @Test("A list switched off everywhere reports it")
    func hiddenEverywhere() {
        var visibility = ListVisibility()
        for surface in DisplaySurface.allCases {
            visibility.setShown(false, .mentions, in: surface)
        }
        #expect(!visibility.isShownAnywhere(.mentions))
        #expect(visibility.shown(in: .window) == [.reviews, .issues])
    }

    /// The order is the same everywhere, whichever entries survive.
    @Test("What is shown keeps the usual order")
    func order() {
        var visibility = ListVisibility()
        visibility.setShown(false, .reviews, in: .popover)
        #expect(visibility.shown(in: .popover) == [.issues, .mentions])
    }

    @Test("The setting survives a round trip through its stored form")
    func roundTrip() {
        var visibility = ListVisibility()
        visibility.setShown(false, .reviews, in: .window)
        visibility.setShown(false, .mentions, in: .menuBar)

        let restored = ListVisibility(storedKeys: visibility.storedKeys)
        #expect(restored == visibility)
        #expect(!restored.isShown(.reviews, in: .window))
        #expect(!restored.isShown(.mentions, in: .menuBar))
        #expect(restored.isShown(.reviews, in: .menuBar))
    }

    @Test("Switching one back on removes it from the stored form")
    func switchingBackOn() {
        var visibility = ListVisibility()
        visibility.setShown(false, .issues, in: .window)
        visibility.setShown(true, .issues, in: .window)
        #expect(visibility.storedKeys.isEmpty)
    }
}

@MainActor
@Suite("Hidden lists leave the window")
struct ListVisibilityStateTests {
    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let state = AppState(settings: Settings(store: defaults))
        state.pullRequests = [pullRequest(id: "1")]
        state.issues = [issue(id: "i1")]
        state.notifications = [notification(id: "n1")]
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

    @Test("Each surface reports the counts it was left with")
    func countsPerSurface() {
        let state = makeState()
        var visibility = state.settings.listVisibility
        visibility.setShown(false, .mentions, in: .menuBar)
        state.settings.listVisibility = visibility

        #expect(state.counts(in: .menuBar).map(\.list) == [.reviews, .issues])
        #expect(state.counts(in: .window).map(\.list) == [.reviews, .issues, .mentions])
        #expect(state.counts(in: .window).map(\.count) == [1, 1, 1])
    }

    /// The content column follows the sidebar selection, so a list hidden
    /// while it is on screen has to hand over -- otherwise it stays visible
    /// with no sidebar entry to leave it by.
    @Test("Hiding the list on screen moves the selection on")
    func selectionMovesOff() {
        let state = makeState()
        state.sidebarSelection = .mentions(repository: nil)

        var visibility = state.settings.listVisibility
        visibility.setShown(false, .mentions, in: .window)
        state.settings.listVisibility = visibility
        state.normaliseSelection()

        #expect(state.sidebarSelection == .pullRequests(repository: nil))
    }

    @Test("A selection that is still shown is left alone")
    func selectionKept() {
        let state = makeState()
        state.sidebarSelection = .myIssues(repository: "a/b")

        var visibility = state.settings.listVisibility
        visibility.setShown(false, .mentions, in: .window)
        state.settings.listVisibility = visibility
        state.normaliseSelection()

        #expect(state.sidebarSelection == .myIssues(repository: "a/b"))
    }

    /// With every list switched off the window still has its other views, so
    /// the selection lands on one of them rather than on nothing.
    @Test("With no list left the window falls back to one's own pull requests")
    func allHidden() {
        let state = makeState()
        var visibility = state.settings.listVisibility
        for list in WatchedList.allCases {
            visibility.setShown(false, list, in: .window)
        }
        state.settings.listVisibility = visibility
        state.normaliseSelection()

        #expect(state.sidebarSelection == .myPullRequests(repository: nil))
        #expect(state.counts(in: .window).isEmpty)
    }

    /// The window opens on the review queue; if that is switched off, the
    /// first thing shown must not be a list that is not in the sidebar.
    @Test("A fresh state never starts on a hidden list")
    func startsOnSomethingVisible() {
        let defaults = UserDefaults(suiteName: "githubmonitor.tests.\(UUID().uuidString)")!
        let settings = Settings(store: defaults)
        var visibility = settings.listVisibility
        visibility.setShown(false, .reviews, in: .window)
        settings.listVisibility = visibility

        let state = AppState(settings: settings)
        #expect(state.sidebarSelection == .myIssues(repository: nil))
    }

    /// Only the lists have switches: "My Pull Requests" and the views below
    /// them are always there.
    @Test("Views without a switch are never moved off")
    func viewsWithoutASwitch() {
        let state = makeState()
        for selection in [SidebarSelection.dashboard, .trends, .settings, .myPullRequests(repository: nil)] {
            state.sidebarSelection = selection
            state.normaliseSelection()
            #expect(state.sidebarSelection == selection)
        }
    }
}
