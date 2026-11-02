import AppKit
import SwiftUI

/// The windows pull requests are reviewed in, one each.
///
/// Windows rather than a card over the main one. The card was inset by
/// thirty-six points on every side so that there was ground beside it to
/// click on, which cost about seven per cent of the window and could not
/// be reclaimed by going full screen -- the border scaled with it. It also
/// held the whole app still: while a diff was up, the lists behind it were
/// visible and dead, and there was no second review to be had at all.
///
/// What it gives up, and this is worth saying plainly: clicking beside the
/// diff no longer puts it away, and neither does Escape. The way out is
/// the way out of any window -- the red light, or Command-W.
@MainActor
final class ReviewWindows: NSObject, NSWindowDelegate {
    /// Called when a window goes away by any route, so whoever opened it
    /// can forget that diff.
    var onClose: ((String) -> Void)?
    /// Asked after a window closes, so the app only drops back to an
    /// accessory once nothing is left on screen.
    var onDidClose: (() -> Void)?

    private struct Open {
        let window: NSWindow
        let host: NSHostingView<DiffOverlay>
    }

    /// Keyed by pull request, which is what makes a second *Review* on the
    /// same one raise the window that is already up rather than open a
    /// rival to it.
    private var open: [String: Open] = [:]
    /// Pull requests whose windows are being taken down by the app itself,
    /// so the close notification does not report them as the user's doing.
    private var closingForGood: Set<String> = []

    var isShowing: Bool { !open.isEmpty }

    /// The reviews on screen, for whoever has to close the ones the state
    /// no longer holds.
    var shownIDs: [String] { Array(open.keys) }

    func isShowing(_ pullRequestID: String) -> Bool { open[pullRequestID] != nil }

    /// Which review a window is showing, for the menu items that act on
    /// whichever one the keyboard is in.
    func pullRequestID(of window: NSWindow?) -> String? {
        guard let window else { return nil }
        return open.first { $0.value.window === window }?.key
    }

    /// Puts a diff on screen, or hands an open window the newer state.
    ///
    /// Handing rather than rebuilding: a window rebuilt from scratch loses
    /// the scroll position, the open folders and the half-written remark
    /// in it, and this is called again on every refresh.
    func show(
        _ content: DiffOverlay,
        for pullRequestID: String,
        title: String,
        subtitle: String,
        unsent: Int
    ) {
        if let entry = open[pullRequestID] {
            entry.host.rootView = content
            entry.window.title = title
            entry.window.subtitle = subtitle
            Self.mark(entry.window, title: title, unsent: unsent)
            return
        }

        let host = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.delegate = self
        window.title = title
        window.subtitle = subtitle
        // The app outlives its windows -- it is a menu bar app -- so a
        // released window would be a dangling delegate on the next open.
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 420)
        // One identifier for every window the app has, the list included,
        // so "Merge All Windows" can gather the lot. Which windows start
        // out together is a separate question, answered below.
        window.tabbingIdentifier = Self.tabbingIdentifier
        // Automatic, not preferred. Preferred means "tab with anything
        // carrying this identifier the moment you are ordered front" --
        // and since the list window carries it too, the first review of
        // the day was swallowed into the list window as a second tab
        // rather than opening. Which windows start out together is
        // decided below; the identifier is only what lets somebody merge
        // them by hand afterwards.
        window.tabbingMode = .automatic

        // Beside a review that is already open, as a tab. Not onto the
        // main window, even though the two may be merged by hand: the
        // first review of the day should not swallow the list you opened
        // it from.
        if let sibling = open.values.first?.window {
            sibling.addTabbedWindow(window, ordered: .above)
        } else {
            window.setFrameAutosaveName(Self.frameName)
            // Nothing saved yet, which is the first review ever opened.
            if !window.setFrameUsingName(Self.frameName) {
                window.setContentSize(Self.defaultSize)
                window.center()
            }
            Self.fit(window)
        }
        Self.mark(window, title: title, unsent: unsent)

        open[pullRequestID] = Open(window: window, host: host)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Raises the window already showing this review, if there is one.
    func raise(_ pullRequestID: String) {
        guard let entry = open[pullRequestID] else { return }
        NSApp.activate(ignoringOtherApps: true)
        entry.window.makeKeyAndOrderFront(nil)
    }

    /// Takes a window away without reporting it as a close, for the cases
    /// where the app is putting it away itself -- signing out.
    func dismiss(_ pullRequestID: String) {
        guard let entry = open[pullRequestID] else { return }
        closingForGood.insert(pullRequestID)
        entry.window.close()
        closingForGood.remove(pullRequestID)
        open[pullRequestID] = nil
        onDidClose?()
    }

    func dismissAll() {
        for id in open.keys { dismiss(id) }
    }

    func windowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let id = pullRequestID(of: window)
        else { return }
        open[id] = nil
        guard !closingForGood.contains(id) else { return }
        onClose?(id)
        // Deferred for the same reason the main window defers it: the
        // window is still closing here, and switching policy mid-close
        // leaves the Dock icon behind.
        DispatchQueue.main.async { [weak self] in self?.onDidClose?() }
    }

    /// A dot on the tab while the review holds remarks nobody has sent.
    ///
    /// In the tab's own title rather than beside it: a native tab is drawn
    /// by the system and takes a string, not a view. The purple is the one
    /// an unsent remark already wears in the diff and in the file tree, so
    /// the three marks are recognisably the same thing.
    private static func mark(_ window: NSWindow, title: String, unsent: Int) {
        guard unsent > 0 else {
            window.tab.attributedTitle = nil
            return
        }
        let text = NSMutableAttributedString(string: "\u{25CF} ")
        text.addAttribute(
            .foregroundColor,
            value: NSColor.systemPurple,
            range: NSRange(location: 0, length: text.length)
        )
        text.append(NSAttributedString(string: title))
        window.tab.attributedTitle = text
    }

    /// Wider than the main window, which is set for lists rather than for
    /// code: two columns of a patch want the room, and this is the first
    /// window in the app that has nothing else to spend it on.
    private static let defaultSize = NSSize(width: 1400, height: 900)

    /// One name for every review window, which is what makes them share a
    /// remembered frame. Forty reviews a month would otherwise be forty
    /// saved rectangles, and nobody arranges a window per pull request.
    private static let frameName = "review"

    /// Shared with the main window, so the two may be merged by hand.
    static let tabbingIdentifier = "GitHubMonitor.window"

    /// Brings a remembered frame back onto the screen that is actually
    /// there. A window saved on a second display and restored without one
    /// comes back somewhere nobody can reach.
    private static func fit(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        if !visible.intersects(frame) {
            frame.origin = CGPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            )
        }
        window.setFrame(frame, display: false)
    }
}
