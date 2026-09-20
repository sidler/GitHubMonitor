import AppKit
import Observation
import SwiftUI

/// Owns the menu bar item, keeps its title in sync with `AppState`, and hosts
/// the popover.
@MainActor
public final class StatusItemController {
    private let state: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let openMainWindow: () -> Void

    public init(state: AppState, openMainWindow: @escaping () -> Void) {
        self.state = state
        self.openMainWindow = openMainWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 460)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                state: state,
                openMainWindow: { [weak self] in
                    self?.closePopover()
                    openMainWindow()
                },
                quit: { NSApp.terminate(nil) }
            )
        )

        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        updateTitle()
        observeState()
    }

    // MARK: - Title

    private func updateTitle() {
        guard let button = statusItem.button else { return }

        let segments = StatusBarTitleBuilder.segments(
            pullRequests: state.pullRequests.count,
            mentions: state.notifications.count,
            style: state.settings.statusBarStyle,
            health: state.health
        )

        let title = NSMutableAttributedString()
        let font = NSFont.menuBarFont(ofSize: 0)
        // Match the menu bar font size exactly: a symbol even one point
        // smaller reads as visibly undersized next to the digits.
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)

        for segment in segments {
            switch segment {
            case .text(let text):
                title.append(NSAttributedString(string: text, attributes: [.font: font]))
            case .symbol(let name):
                guard
                    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                        .withSymbolConfiguration(configuration)
                else {
                    // Fall back to the symbol name rather than dropping the
                    // segment silently -- a missing glyph should be visible.
                    title.append(NSAttributedString(string: name, attributes: [.font: font]))
                    continue
                }
                image.isTemplate = true
                let attachment = NSTextAttachment()
                attachment.image = image
                // Sit the glyph on the baseline. Centring it on the cap height
                // looks like the more correct choice but pushes SF Symbols
                // noticeably below the digits, because they are taller than
                // the cap height by design.
                attachment.bounds = CGRect(origin: .zero, size: image.size)
                title.append(NSAttributedString(attachment: attachment))
            }
        }

        button.attributedTitle = title
        button.toolTip = StatusBarTitleBuilder.accessibilityLabel(
            pullRequests: state.pullRequests.count,
            mentions: state.notifications.count,
            health: state.health
        )
    }

    /// `@Observable` has no publisher, so we re-arm the tracking closure after
    /// every change.
    private func observeState() {
        withObservationTracking {
            _ = state.pullRequests.count
            _ = state.notifications.count
            _ = state.hasToken
            _ = state.loadState
            _ = state.settings.statusBarStyle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateTitle()
                self.observeState()
            }
        }
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    public func showPopover(activating: Bool = false) {
        guard let button = statusItem.button, !popover.isShown else { return }
        // A transient popover closes as soon as another app is frontmost, so
        // opening it without a click on the status item needs the activation
        // that the click would otherwise provide.
        if activating {
            NSApp.activate(ignoringOtherApps: true)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}
