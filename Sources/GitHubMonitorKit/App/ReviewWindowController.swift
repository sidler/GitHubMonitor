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
    /// Asked to turn a review's half-written remarks into unsent ones,
    /// when that is what somebody chose on the way out.
    var keepUnfinished: ((String) -> Void)?

    private struct Open {
        let window: NSWindow
        let host: NSHostingView<DiffOverlay>
    }

    /// Keyed by pull request, which is what makes a second *Review* on the
    /// same one raise the window that is already up rather than open a
    /// rival to it.
    private var open: [String: Open] = [:]
    /// The work being done ahead of each window's scroll, so it can be
    /// called off when the window goes.
    private var priming: [String: Task<Void, Never>] = [:]
    /// The boxes remarks are being written in, one set per review.
    ///
    /// Here rather than in the view that draws them, because they have to
    /// outlive it by exactly one question: a window being closed with
    /// words in a box is the moment to ask what should become of them,
    /// and by the time the view is gone there is nothing left to ask
    /// about.
    private var drafting: [String: DraftBoxes] = [:]
    /// Pull requests whose windows are being taken down by the app itself,
    /// so the close notification does not report them as the user's doing.
    private var closingForGood: Set<String> = []

    var isShowing: Bool { !open.isEmpty }

    /// The reviews on screen, for whoever has to close the ones the state
    /// no longer holds.
    var shownIDs: [String] { Array(open.keys) }

    func isShowing(_ pullRequestID: String) -> Bool { open[pullRequestID] != nil }

    /// The boxes for this review, made the first time they are asked for
    /// and the same ones every time after.
    func boxes(for pullRequestID: String) -> DraftBoxes {
        if let here = drafting[pullRequestID] { return here }
        let made = DraftBoxes()
        drafting[pullRequestID] = made
        return made
    }

    /// Asks what should become of remarks written but not added, then
    /// carries on -- or does not, which is what Cancel is for.
    ///
    /// Used by every way out of a review, the close button and Done
    /// alike. Half-written remarks are the one thing in a review that is
    /// nowhere else: a draft remark is kept on disk and an unsent review
    /// survives a restart, but words still in the box are only in the
    /// box.
    func confirmClosing(_ pullRequestID: String, then: @escaping () -> Void) {
        let unfinished = drafting[pullRequestID]?.unfinished ?? []
        guard !unfinished.isEmpty, let window = open[pullRequestID]?.window else {
            return then()
        }

        let alert = NSAlert()
        alert.messageText = unfinished.count == 1
            ? "One remark has been written but not added."
            : "\(unfinished.count) remarks have been written but not added."
        alert.informativeText = """
            Keeping them puts them into the review as unsent remarks, \
            where you can still change or delete them before you send it.
            """
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        // Discard throws writing away, so it is not the one a stray
        // Return lands on.
        alert.buttons[1].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] answer in
            switch answer {
            case .alertFirstButtonReturn:
                self?.keepUnfinished?(pullRequestID)
                then()
            case .alertSecondButtonReturn:
                then()
            default:
                break
            }
        }
    }

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
        unsent: Int,
        priming work: @autoclosure () -> Task<Void, Never>
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
        // Only for a window being built: handing an open one the current
        // state happens on every refresh, and starting this again each
        // time would be the same work over and over.
        priming[pullRequestID] = work()
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
        priming[pullRequestID]?.cancel()
        priming[pullRequestID] = nil
        entry.window.close()
        closingForGood.remove(pullRequestID)
        open[pullRequestID] = nil
        drafting[pullRequestID] = nil
        onDidClose?()
    }

    func dismissAll() {
        for id in open.keys { dismiss(id) }
    }

    /// The red light and Command-W, which is where the question belongs.
    ///
    /// `close()` does not come through here, which is what lets the
    /// answer take the window down without being asked a second time.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard
            let id = pullRequestID(of: sender),
            !(drafting[id]?.unfinished.isEmpty ?? true)
        else { return true }
        confirmClosing(id) { [weak self] in self?.open[id]?.window.close() }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let id = pullRequestID(of: window)
        else { return }
        open[id] = nil
        priming[id]?.cancel()
        priming[id] = nil
        drafting[id] = nil
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
