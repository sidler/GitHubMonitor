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
