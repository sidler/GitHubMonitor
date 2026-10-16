import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("Setting and clearing one label")
struct LabelChangeTests {
    private let bug = IssueLabel(id: "LA_1", name: "bug", color: "d73a4a")
    private let session = IssueLabel(id: "LA_2", name: "session", color: "0e8a16")

    @Test("Setting one adds it, in its place in the order")
    func adds() {
        let after = LabelChange.after([session], setting: bug, to: true)
        #expect(after.map(\.name) == ["bug", "session"])
    }

    @Test("Clearing one takes it off and leaves the rest")
    func removes() {
        let after = LabelChange.after([bug, session], setting: bug, to: false)
        #expect(after.map(\.name) == ["session"])
    }

    /// Pressed twice in a row, or pressed on something already set: the
    /// answer is the same set either way, and never the same label twice.
    @Test("Setting one that is already there changes nothing")
    func idempotent() {
        let after = LabelChange.after([bug, session], setting: bug, to: true)
        #expect(after.map(\.id) == ["LA_1", "LA_2"])
    }

    @Test("Clearing one that is not there changes nothing")
    func clearingAbsent() {
        #expect(LabelChange.after([session], setting: bug, to: false).map(\.id) == ["LA_2"])
    }

    /// By id, because two labels can read alike across repositories and
    /// the id is what GitHub is told.
    @Test("A label of the same name but another id is a different label")
    func byID() {
        let elsewhere = IssueLabel(id: "LA_9", name: "bug", color: "d73a4a")
        let after = LabelChange.after([bug], setting: elsewhere, to: false)
        #expect(after.map(\.id) == ["LA_1"])
    }

    /// The list keeps its own copy of an issue's labels and the pane
    /// falls back to it, so a change has to reach it too.
    @Test("An issue can be handed different labels")
    func carriesNewLabels() {
        let issue = IssueItem(
            id: "I_1", number: 1, title: "t", repository: "octo/server",
            author: "a", authorAvatarURL: nil,
            url: URL(string: "https://github.com")!,
            createdAt: .now, updatedAt: .now, comments: 0, labels: [bug]
        )
        #expect(issue.withLabels([session]).labels.map(\.name) == ["session"])
        #expect(issue.labels.map(\.name) == ["bug"])
    }
}
