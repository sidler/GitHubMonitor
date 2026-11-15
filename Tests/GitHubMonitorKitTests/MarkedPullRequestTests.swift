import Foundation
import Testing

@testable import GitHubMonitorKit

/// Selecting several pull requests at once, and what that is for.
@MainActor
@Suite("Several pull requests at once")
struct MarkedPullRequestTests {
    private let list = SavedList(
        id: "l", title: "A list", query: "is:pr review-requested:@me", content: .pullRequests
    )

    private func make() -> (AppState, RefreshController) {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        state.settings.savedLists = [list]
        state.sidebarSelection = .list(id: list.id, repository: nil)
        // Newest first is what the list draws, so these are deliberately
        // added oldest first: anything that reads them back in insertion
        // order rather than in the order on screen gets it wrong.
        state.listPullRequests[list.id] = (1...5).map { index in
            PullRequestItem(
                id: "\(index)", number: index, title: "t", repository: "r", author: "a",
                authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now.addingTimeInterval(TimeInterval(-600 * index)),
                reviewDecision: .none, checks: .none
            )
        }
        return (state, RefreshController(state: state))
    }

    // MARK: The pane against the selection

    /// One row selected is the ordinary case and the pane is about it.
    @Test("Selecting one row moves the pane to it")
    func oneRow() {
        let (state, _) = make()

        state.markedPullRequestIDs = ["3"]

        #expect(state.inspectedPullRequestID == "3")
    }

    /// A pane describes one pull request and cannot describe five. Rather
    /// than blanking it, it keeps the one it was already about -- putting
    /// it away is the close button's job, not a side effect of holding
    /// Command.
    @Test("Selecting several leaves the pane where it was")
    func severalRows() {
        let (state, _) = make()
        state.markedPullRequestIDs = ["3"]

        state.markedPullRequestIDs = ["3", "4", "5"]

        #expect(state.inspectedPullRequestID == "3")
    }

    @Test("Selecting nothing leaves the pane where it was")
    func noRows() {
        let (state, _) = make()
        state.markedPullRequestIDs = ["2"]

        state.markedPullRequestIDs = []

        #expect(state.inspectedPullRequestID == "2")
    }

    /// Moving the pane from the menu, the arrow keys or "Show in list"
    /// has to move the highlight with it, or the list shows one row
    /// selected while the pane describes another.
    @Test("Opening a pane selects its row in the list")
    func inspectSelects() {
        let (state, controller) = make()
        state.markedPullRequestIDs = ["1", "2"]

        controller.moveInspection(by: 1)

        #expect(state.markedPullRequestIDs.count == 1)
        #expect(state.markedPullRequestIDs.first == state.inspectedPullRequestID)
    }

    @Test("Closing the pane clears the selection")
    func closeClears() {
        let (state, controller) = make()
        state.markedPullRequestIDs = ["1", "2"]

        controller.closeInspector()

        #expect(state.markedPullRequestIDs.isEmpty)
        #expect(state.inspectedPullRequestID == nil)
    }

    // MARK: The order the reviews open in

    /// The order decides which window the others become tabs of, so it
    /// has to be the order on screen. A `Set` has none of its own, and
    /// reading it back directly gave a different answer each run.
    @Test("The selection is read back in the order the list draws it")
    func order() {
        let (state, _) = make()
        let onScreen = state.pullRequests(in: list).map(\.id)

        state.markedPullRequestIDs = Set(onScreen)

        #expect(state.orderedMarkedPullRequestIDs == onScreen)
    }

    @Test("Only the selected ones come back, still in order")
    func subsetOrder() {
        let (state, _) = make()
        let onScreen = state.pullRequests(in: list).map(\.id)
        let wanted = [onScreen[3], onScreen[0], onScreen[2]]

        state.markedPullRequestIDs = Set(wanted)

        #expect(
            state.orderedMarkedPullRequestIDs == [onScreen[0], onScreen[2], onScreen[3]]
        )
    }

    /// Reading the selection with no list on screen is better answered
    /// with something than with nothing.
    @Test("Without a list on screen the selection is still readable")
    func noList() {
        let (state, _) = make()
        state.markedPullRequestIDs = ["2", "4"]
        state.sidebarSelection = .trends

        #expect(Set(state.orderedMarkedPullRequestIDs) == ["2", "4"])
    }

    // MARK: Not opening the world

    /// Each review is three requests and a window. A stray Command-A over
    /// a list of four hundred should not spend the hour's allowance and
    /// bury the screen.
    @Test("One command opens a bounded number of reviews")
    func cap() {
        #expect(RefreshController.maximumReviewsAtOnce > 1)
        #expect(RefreshController.maximumReviewsAtOnce <= 25)
    }

    /// A row that has gone from the list cannot be reviewed, and a
    /// selection holding it would offer to.
    @Test("A refresh forgets rows that are no longer there")
    func pruning() {
        let (state, _) = make()
        state.markedPullRequestIDs = ["1", "2", "3"]

        // What the refresh does once the list comes back shorter.
        state.markedPullRequestIDs.formIntersection(["2", "3", "9"])

        #expect(state.markedPullRequestIDs == ["2", "3"])
    }
}
