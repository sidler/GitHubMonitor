import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Notification filter")
struct NotificationFilterTests {
    private func item(_ id: String, reason: NotificationReason, repository: String = "octo/server") -> NotificationItem {
        NotificationItem(
            id: id, title: "t", repository: repository, avatarURL: nil,
            reason: reason, updatedAt: .now, subjectType: "Issue",
            latestCommentAPIURL: nil, subjectAPIURL: nil
        )
    }

    private var sample: [NotificationItem] {
        [
            item("1", reason: .mention),
            item("2", reason: .teamMention),
            item("3", reason: .subscribed),
            item("4", reason: .mention, repository: "avery/dotfiles"),
        ]
    }

    @Test("Only selected reasons are kept")
    func reasonFilter() {
        let result = NotificationFilter.apply(sample, reasons: [.mention], repositoryFilters: [])
        #expect(result.map(\.id) == ["1", "4"])
    }

    @Test("Several reasons can be selected at once")
    func multipleReasons() {
        let result = NotificationFilter.apply(sample, reasons: [.mention, .teamMention], repositoryFilters: [])
        #expect(result.map(\.id) == ["1", "2", "4"])
    }

    /// Unticking every reason should silence the badge, not open it up --
    /// treating "empty" as "everything" would be a nasty surprise.
    @Test("No selected reason means nothing is shown")
    func emptySelection() {
        #expect(NotificationFilter.apply(sample, reasons: [], repositoryFilters: []).isEmpty)
    }

    @Test("The repository filter applies too")
    func repositoryFilter() {
        let result = NotificationFilter.apply(
            sample, reasons: [.mention], repositoryFilters: ["octo"]
        )
        #expect(result.map(\.id) == ["1"])
    }

    @Test("Owner matching does not leak into similarly named owners")
    func ownerPrefix() {
        let items = [
            item("1", reason: .mention, repository: "octo/server"),
            item("2", reason: .mention, repository: "octoics/core"),
        ]
        let result = NotificationFilter.apply(items, reasons: [.mention], repositoryFilters: ["octo"])
        #expect(result.map(\.id) == ["1"])
    }
}
