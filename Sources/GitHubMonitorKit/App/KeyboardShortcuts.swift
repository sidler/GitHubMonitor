import AppKit

/// Keyboard shortcuts for the app's own windows.
///
/// An accessory app shows no menu bar, so the usual route — a Preferences
/// menu item carrying the shortcut — is not available. A local event monitor
/// gives the same behaviour for the windows this app owns, without claiming
/// the combination system-wide.
@MainActor
final class KeyboardShortcuts {
    private var monitor: Any?
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    /// Explicit rather than in `deinit`: a nonisolated deinit cannot touch
    /// main-actor state under Swift 6's concurrency rules.
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Returns nil to swallow the event, or the event to pass it on.
    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command, event.charactersIgnoringModifiers == "," else {
            return event
        }
        openSettings()
        return nil
    }
}
