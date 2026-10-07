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
