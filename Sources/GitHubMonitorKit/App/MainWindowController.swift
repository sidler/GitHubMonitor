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
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "GitHub Monitor"
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            // Let the content run under the title bar so the sidebar reaches
            // the top of the window, as in Finder and Mail.
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: MainWindowView(state: state, controller: controller))
            self.window = window
        }

        // Becoming a regular app is what puts the window in the app switcher
        // and shows the menu bar; it has to happen before activating.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        // Back to an agent once the window is gone. Deferred because the
        // window is still closing at this point, and switching policy
        // mid-close leaves the Dock icon behind.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
