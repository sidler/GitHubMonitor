import AppKit
import SwiftUI

/// The optional full view: complete lists, previews and settings.
@MainActor
public final class MainWindowController {
    private let state: AppState
    private let controller: RefreshController
    private var window: NSWindow?

    public init(state: AppState, controller: RefreshController) {
        self.state = state
        self.controller = controller
    }

    public func show(selecting tab: MainWindowTab? = nil) {
        if let tab {
            state.selectedTab = tab
        }

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 900),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "GitHub Monitor"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainWindowView(state: state, controller: controller))
            self.window = window
        }

        // LSUIElement apps are not activated by ordering a window front alone.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
