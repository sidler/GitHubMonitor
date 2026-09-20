import AppKit
import SwiftUI

/// The optional full view: complete lists, previews and settings.
@MainActor
public final class MainWindowController {
    private let state: AppState
    private var window: NSWindow?

    public init(state: AppState) {
        self.state = state
    }

    public func show(selecting tab: MainWindowTab? = nil) {
        if let tab {
            state.selectedTab = tab
        }

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "GitHub Monitor"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainWindowView(state: state))
            self.window = window
        }

        // LSUIElement apps are not activated by ordering a window front alone.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
