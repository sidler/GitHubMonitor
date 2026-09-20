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
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize - 1, weight: .regular)

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
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}
