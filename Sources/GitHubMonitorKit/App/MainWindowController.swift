import AppKit
import SwiftUI

/// The optional full view: complete lists, previews and settings.
///
/// While this window is open the app switches to a regular activation policy,
/// so it appears in the Dock and the app switcher and its menu bar is shown.
/// Closing the window drops back to an accessory, which is what keeps the menu
/// bar item from carrying a Dock icon around for a status readout.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private let controller: RefreshController
    private var window: NSWindow?

    public init(state: AppState, controller: RefreshController) {
        self.state = state
        self.controller = controller
        super.init()
    }

    public func show(selecting tab: MainWindowTab? = nil) {
        switch tab {
        case .pullRequests: state.sidebarSelection = .pullRequests(repository: nil)
        case .mentions: state.sidebarSelection = .mentions(repository: nil)
        case .settings: state.sidebarSelection = .settings
        case nil: break
        }

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "GitHub Monitor"
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.styleMask.insert(.fullSizeContentView)
            // A unified toolbar puts the title and the list's controls into
            // the title bar, which would otherwise sit empty above a row
            // doing the same job. It also gives the sidebar its full height.
            window.toolbarStyle = .unified
            // contentViewController rather than contentView: SwiftUI's
            // .toolbar and .navigationTitle only reach the window through a
            // hosting controller.
            window.contentViewController = NSHostingController(
                rootView: MainWindowView(
                    state: state,
                    controller: controller,
                    ensureRoomForInspector: { [weak self] in self?.ensureRoomForInspector() }
                )
            )
            self.window = window
        }

        // Becoming a regular app is what puts the window in the app switcher
        // and shows the menu bar; it has to happen before activating.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Widens the window when the detail pane opens into one too narrow to
    /// hold three columns, rather than squeezing the list to shreds.
    public func ensureRoomForInspector() {
        guard let window, window.frame.width < Self.widthWithInspector else { return }
        var frame = window.frame
        // Grow to the right, but stay on screen.
        let available = window.screen?.visibleFrame ?? frame
        frame.size.width = Self.widthWithInspector
        if frame.maxX > available.maxX {
            frame.origin.x = max(available.minX, available.maxX - frame.width)
        }
        window.setFrame(frame, display: true, animate: true)
    }

    private static let widthWithInspector: CGFloat = 1060

    public func windowWillClose(_ notification: Notification) {
        // Back to an agent once the window is gone. Deferred because the
        // window is still closing at this point, and switching policy
        // mid-close leaves the Dock icon behind.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
