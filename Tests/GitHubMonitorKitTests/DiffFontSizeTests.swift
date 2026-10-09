import Foundation
import Testing
@testable import GitHubMonitorKit

@MainActor
@Suite("How large the diff's text is")
struct DiffFontSizeTests {
    private func settings() -> Settings {
        Settings(store: TestDefaults.make())
    }

    /// The whole point of the chosen default: switching this app on after
    /// the change should not move a single line of any diff.
    @Test("A fresh install reads at the size it always did")
    func fresh() {
        #expect(settings().diffFontSize == Settings.defaultDiffFontSize)
    }

    @Test("Stepping moves by a point and stops at the ends")
    func stepping() {
        let settings = settings()
        settings.changeDiffFontSize(by: 1)
        #expect(settings.diffFontSize == Settings.defaultDiffFontSize + 1)

        // Held down past the end: the size stops, the app does not.
        for _ in 0..<50 { settings.changeDiffFontSize(by: 1) }
        #expect(settings.diffFontSize == Settings.largestDiffFontSize)
        for _ in 0..<50 { settings.changeDiffFontSize(by: -1) }
        #expect(settings.diffFontSize == Settings.smallestDiffFontSize)

        settings.resetDiffFontSize()
        #expect(settings.diffFontSize == Settings.defaultDiffFontSize)
    }

    /// Preferences are a file anything can write, and a size of zero would
    /// leave a diff nobody can read and no obvious way back.
    ///
    /// The expected sizes are written out rather than read from the range,
    /// so widening the range has to come past this test rather than quietly
    /// agreeing with itself.
    @Test(
        "A size written straight into preferences is clamped on the way in",
        arguments: [(0.0, 8.0), (400.0, 20.0), (-3.0, 8.0), (12.4, 12.0)]
    )
    func clampedOnRead(stored: Double, expected: Double) {
        let store = TestDefaults.make()
        store.set(stored, forKey: "diffFontSize")
        #expect(Settings(store: store).diffFontSize == expected)
    }

    @Test("Assigning out of range is clamped too, and only the clamp is stored")
    func clampedOnWrite() {
        let store = TestDefaults.make()
        let settings = Settings(store: store)
        settings.diffFontSize = 99
        #expect(settings.diffFontSize == Settings.largestDiffFontSize)
        #expect(store.object(forKey: "diffFontSize") as? Double == Settings.largestDiffFontSize)
    }

    @Test("The size outlives the window it was chosen in")
    func persists() {
        let name = TestDefaults.reserveName()
        let first = Settings(store: UserDefaults(suiteName: name)!)
        first.diffFontSize = 14
        #expect(Settings(store: UserDefaults(suiteName: name)!).diffFontSize == 14)
    }
}


@MainActor
@Suite("How wide the file list beside the diff is")
struct DiffSidebarWidthTests {
    @Test("A fresh install opens at the width it always did")
    func fresh() {
        let settings = Settings(store: TestDefaults.make())
        #expect(settings.diffSidebarWidth == Settings.defaultDiffSidebarWidth)
    }

    /// Dragged past either end the edge stops, rather than leaving a list
    /// of no width or one that has eaten the diff.
    @Test(
        "A width out of range is clamped",
        arguments: [(0.0, 160.0), (-50.0, 160.0), (900.0, 560.0), (300.4, 300.0)]
    )
    func clamped(asked: Double, expected: Double) {
        let settings = Settings(store: TestDefaults.make())
        settings.diffSidebarWidth = asked
        #expect(settings.diffSidebarWidth == expected)
    }

    /// Preferences are a file anything can write, and a list of no width
    /// is a diff with no way back to its files.
    @Test("A width written straight into preferences is clamped on the way in")
    func clampedOnRead() {
        let store = TestDefaults.make()
        store.set(2.0, forKey: "diffSidebarWidth")
        #expect(Settings(store: store).diffSidebarWidth == Settings.narrowestDiffSidebar)
    }

    /// It is a judgement about one person's repositories, and nobody wants
    /// to make it twice.
    @Test("The width outlives the diff it was set in")
    func persists() {
        let name = TestDefaults.reserveName()
        Settings(store: UserDefaults(suiteName: name)!).diffSidebarWidth = 340
        #expect(Settings(store: UserDefaults(suiteName: name)!).diffSidebarWidth == 340)
    }
}


/// How large the panel of linked items was left.
@MainActor
@Suite("The size of the linked panel")
struct LinkedPanelSizeTests {
    private func settings() -> Settings {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        return Settings(store: store)
    }

    @Test("It starts at a readable width and takes its height from the cards")
    func defaults() {
        let settings = settings()
        #expect(settings.linkedPanelWidth == Settings.defaultLinkedPanelWidth)
        // Absent, not zero: until it is dragged the panel is as tall as
        // what it holds.
        #expect(settings.linkedPanelHeight == nil)
    }

    @Test("Both are clamped, like every other number read from preferences")
    func clamped() {
        let settings = settings()
        settings.linkedPanelWidth = 10
        #expect(settings.linkedPanelWidth == Settings.narrowestLinkedPanel)
        settings.linkedPanelWidth = 4_000
        #expect(settings.linkedPanelWidth == Settings.widestLinkedPanel)

        settings.linkedPanelHeight = 4
        #expect(settings.linkedPanelHeight == Settings.shortestLinkedPanel)
        settings.linkedPanelHeight = 5_000
        #expect(settings.linkedPanelHeight == Settings.tallestLinkedPanel)
    }

    @Test("What it was left at is what it opens at next time")
    func kept() {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        let first = Settings(store: store)
        first.linkedPanelWidth = 640
        first.linkedPanelHeight = 500

        let second = Settings(store: store)
        #expect(second.linkedPanelWidth == 640)
        #expect(second.linkedPanelHeight == 500)
    }

    /// Double-clicking the corner gives the panel back to its contents.
    @Test("Clearing the height goes back to fitting the cards")
    func cleared() {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        let settings = Settings(store: store)
        settings.linkedPanelHeight = 500
        settings.linkedPanelHeight = nil

        #expect(Settings(store: store).linkedPanelHeight == nil)
    }
}


/// Where the diff is, and where it has been asked to go. Two things, not
/// one: `scrollPosition(id:)` holds whatever it is given, and giving it
/// back the file you are reading meant every change of content -- opening
/// a review comment, most of all -- dragged the page to that file's top.
@MainActor
@Suite("Going somewhere in the diff, and being somewhere")
struct DiffPlaceTests {
    @Test("Being somewhere is not a request to go there")
    func reportingIsNotGoing() {
        let place = DiffPlace()
        place.path = "src/Thing.php"

        // What the scroll view reports leaves nothing for it to hold on
        // to, so the next thing that grows moves only what is below it.
        #expect(place.wanted == nil)
    }

    @Test("Going somewhere sets both")
    func going() {
        let place = DiffPlace()
        place.go(to: "src/Other.php")

        #expect(place.wanted == "src/Other.php")
        // And the list beside the diff marks it at once, rather than
        // waiting for the scroll to report back.
        #expect(place.path == "src/Other.php")
    }
}
