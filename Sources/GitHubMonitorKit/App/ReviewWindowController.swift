import AppKit
import SwiftUI

/// The window a pull request is reviewed in.
///
/// A window rather than a card over the main one. The card was inset by
/// thirty-six points on every side so that there was ground beside it to
/// click on, which cost about seven per cent of the window and could not
/// be reclaimed by going full screen -- the border scaled with it. It also
/// held the whole app still: while a diff was up, the lists behind it were
/// visible and dead.
///
/// What it gives up, and this is worth saying plainly: clicking beside the
/// diff no longer puts it away, and neither does Escape. The way out is
/// the way out of any window -- the red light, or Command-W.
@MainActor
final class ReviewWindowController: NSObject, NSWindowDelegate {
    /// Called when the window goes away by any route, so whoever opened it
    /// can forget the diff.
    var onClose: (() -> Void)?
    /// Asked after the window closes, so the app only drops back to an
    /// accessory once nothing is left on screen.
    var onDidClose: (() -> Void)?

    private var window: NSWindow?
    private var host: NSHostingView<DiffOverlay>?
    /// Set while the window is being taken down on purpose, so the close
    /// notification does not report it as the user's doing.
    private var isClosingForGood = false

    var isOpen: Bool { window?.isVisible ?? false }

    /// Puts the diff on screen, or hands an open window the newer state.
    ///
    /// Handing rather than rebuilding: a window rebuilt from scratch loses
    /// the scroll position, the open folders and the half-written remark
    /// in it, and this is called again on every refresh.
    func show(_ content: DiffOverlay, title: String, subtitle: String) {
        if let window, let host {
            host.rootView = content
            window.title = title
            window.subtitle = subtitle
            window.makeKeyAndOrderFront(nil)
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
        // One remembered frame for all of them rather than one per pull
        // request: forty reviews a month would be forty saved rectangles,
        // and nobody arranges a window per pull request.
        window.setFrameAutosaveName(Self.frameName)
        // Nothing saved yet, which is the first review ever opened.
        if !window.setFrameUsingName(Self.frameName) {
            window.setContentSize(Self.defaultSize)
            window.center()
        }
        Self.fit(window)

        self.window = window
        self.host = host
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Takes the window away without reporting it as a close, for the
    /// cases where the app is putting it away itself -- signing out.
    func dismiss() {
        guard let window else { return }
        isClosingForGood = true
        window.close()
        isClosingForGood = false
        self.window = nil
        host = nil
        onDidClose?()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosingForGood else { return }
        window = nil
        host = nil
        onClose?()
        // Deferred for the same reason the main window defers it: the
        // window is still closing here, and switching policy mid-close
        // leaves the Dock icon behind.
        DispatchQueue.main.async { [weak self] in self?.onDidClose?() }
    }

    /// Wider than the main window, which is set for lists rather than for
    /// code: two columns of a patch want the room, and this is the first
    /// window in the app that has nothing else to spend it on.
    private static let defaultSize = NSSize(width: 1400, height: 900)

    /// One name for every review window, which is what makes them share a
    /// remembered frame.
    private static let frameName = "review"

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
