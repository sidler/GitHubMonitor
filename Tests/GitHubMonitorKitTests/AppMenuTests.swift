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
            diffLayout: { .unified }, setDiffLayout: { _ in },
            diffPaging: { .scroll }, setDiffPaging: { _ in }
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
