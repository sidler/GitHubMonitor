import AppKit
import Testing
@testable import GitHubMonitorKit

/// What the keyboard does to a window, and what it does to the app.
///
/// This lives in the menu bar: its job is to keep watching after you have
/// finished looking. Command-Q is the keystroke every Mac user presses to
/// clear a window off the screen, and here that must not also stop it
/// doing its job -- so it closes the window, and quitting is a modifier
/// further along.
@MainActor
@Suite("Command-Q puts the window away")
struct AppMenuTests {
    private func menu() -> NSMenu {
        // The menu hangs the Services submenu off the application, and in
        // a test process there is no application until one is asked for.
        _ = NSApplication.shared
        return AppMenu.build(
            appName: "GitHub Monitor",
            openSettings: {}, refresh: {}, moveDetail: { _ in }, closeDetail: {},
            changeDiffFontSize: { _ in }, resetDiffFontSize: {},
            showsDiffLineNumbers: { true }, toggleDiffLineNumbers: {},
            showsDiffInspector: { false }, toggleDiffInspector: {},
            diffLayout: { .unified }, setDiffLayout: { _ in },
            diffPaging: { .scroll }, setDiffPaging: { _ in },
            stepDiffFile: { _ in }, canStepDiffFile: { true },
            reviewSelection: {}, selectedForReview: { 0 }
        )
    }

    private func items() -> [NSMenuItem] {
        menu().items.first?.submenu?.items ?? []
    }

    private func item(_ title: String) -> NSMenuItem? {
        items().first { $0.title == title }
    }

    @Test("It closes the window rather than ending the app")
    func closes() throws {
        let close = try #require(item("Close Window"))
        #expect(close.keyEquivalent == "q")
        #expect(close.keyEquivalentModifierMask == [.command])
        #expect(close.action == #selector(NSWindow.performClose(_:)))
    }

    /// Still in the app menu where anybody would look for it, and still on
    /// the keyboard -- one modifier further, so it cannot be hit by
    /// reflex.
    @Test("Quitting is a modifier further along")
    func quits() throws {
        let quit = try #require(item("Quit GitHub Monitor"))
        #expect(quit.keyEquivalent == "q")
        #expect(quit.keyEquivalentModifierMask == [.command, .option])
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
    }

    /// Both on `q`, so whichever is listed first would win a plain
    /// Command-Q. The one that closes has to come first.
    @Test("The closing one is the one Command-Q finds")
    func order() throws {
        let titles = items().map(\.title)
        let close = try #require(titles.firstIndex(of: "Close Window"))
        let quit = try #require(titles.firstIndex(of: "Quit GitHub Monitor"))
        #expect(close < quit)
    }

    /// The window still closes the way every other Mac window does.
    @Test("Command-W is untouched")
    func closeStaysOnW() throws {
        let file = try #require(menu().items.first { $0.submenu?.title == "File" })
        let close = try #require(file.submenu?.items.first { $0.title == "Close" })
        #expect(close.keyEquivalent == "w")
        #expect(close.keyEquivalentModifierMask == [.command])
    }
}

/// The command that opens a review per selected row.
@MainActor
@Suite("Reviewing what the list has selected")
struct ReviewSelectionMenuTests {
    private func fileMenu(selected: Int) -> [NSMenuItem] {
        _ = NSApplication.shared
        let main = AppMenu.build(
            appName: "GitHub Monitor",
            openSettings: {}, refresh: {}, moveDetail: { _ in }, closeDetail: {},
            changeDiffFontSize: { _ in }, resetDiffFontSize: {},
            showsDiffLineNumbers: { true }, toggleDiffLineNumbers: {},
            showsDiffInspector: { false }, toggleDiffInspector: {},
            diffLayout: { .unified }, setDiffLayout: { _ in },
            diffPaging: { .scroll }, setDiffPaging: { _ in },
            stepDiffFile: { _ in }, canStepDiffFile: { true },
            reviewSelection: {}, selectedForReview: { selected }
        )
        return main.items.first { $0.submenu?.title == "File" }?.submenu?.items ?? []
    }

    /// The title and whether it may be used are both decided when AppKit
    /// asks, in the moment before the menu is drawn -- not when it was
    /// built. So the answer is taken from the asking.
    private func review(selected: Int) -> (item: NSMenuItem, usable: Bool)? {
        guard
            let item = fileMenu(selected: selected).first(where: {
                $0.title.contains("Review")
            }),
            let validating = item as? NSMenuItemValidation
        else { return nil }
        return (item, validating.validateMenuItem(item))
    }

    @Test("With nothing selected it is there but cannot be used")
    func nothingSelected() {
        let found = review(selected: 0)

        #expect(found != nil)
        #expect(found?.usable == false)
    }

    /// The count is in the name because a command that opens twelve
    /// windows should say twelve before it is pressed.
    @Test("It says how many it will open")
    func named() {
        #expect(review(selected: 1)?.item.title == "Review Selected Pull Request")
        #expect(review(selected: 4)?.item.title == "Review 4 Selected Pull Requests")
        #expect(review(selected: 1)?.usable == true)
    }

    @Test("It carries a shortcut that is not the refresh one")
    func shortcut() {
        let item = review(selected: 2)?.item

        #expect(item?.keyEquivalent == "r")
        #expect(item?.keyEquivalentModifierMask == [.command, .shift])
    }
}

/// Stepping through a diff's files from the keyboard.
@Suite("Option-arrow steps through the files of a diff")
@MainActor
struct DiffStepMenuTests {
    private func menu(canStep: @escaping () -> Bool = { true }) -> [NSMenuItem] {
        _ = NSApplication.shared
        let main = AppMenu.build(
            appName: "GitHub Monitor",
            openSettings: {}, refresh: {}, moveDetail: { _ in }, closeDetail: {},
            changeDiffFontSize: { _ in }, resetDiffFontSize: {},
            showsDiffLineNumbers: { true }, toggleDiffLineNumbers: {},
            showsDiffInspector: { false }, toggleDiffInspector: {},
            diffLayout: { .unified }, setDiffLayout: { _ in },
            diffPaging: { .scroll }, setDiffPaging: { _ in },
            stepDiffFile: { _ in }, canStepDiffFile: canStep,
            reviewSelection: {}, selectedForReview: { 0 }
        )
        // The View menu is the one that carries them.
        return main.items.first { $0.submenu?.title == "View" }?.submenu?.items ?? []
    }

    private func item(_ title: String, canStep: @escaping () -> Bool = { true }) -> NSMenuItem? {
        menu(canStep: canStep).first { $0.title == title }
    }

    /// On the buttons in the diff they never fired: a key equivalent on a
    /// SwiftUI button inside a hosted view only works while that view
    /// holds the keyboard, and the overlay never does.
    @Test("Both are in the View menu, on the option arrows")
    func present() throws {
        let back = try #require(item("Previous File"))
        let on = try #require(item("Next File"))
        #expect(back.keyEquivalentModifierMask == [.option])
        #expect(on.keyEquivalentModifierMask == [.option])
        #expect(back.keyEquivalent != on.keyEquivalent)
    }

    /// The point of the grey is what it hands back: a disabled item does
    /// not swallow its key equivalent, so option-left goes on being
    /// word-left in the box where a review remark is written.
    @Test("Disabled where there is nothing to step through")
    func disabled() throws {
        let item = try #require(item("Next File", canStep: { false }))
        let validator = try #require(item as? NSMenuItemValidation)
        #expect(!validator.validateMenuItem(item))

        let usable = try #require(self.item("Next File", canStep: { true }))
        let other = try #require(usable as? NSMenuItemValidation)
        #expect(other.validateMenuItem(usable))
    }
}
