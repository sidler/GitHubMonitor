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

    public init(
        state: AppState,
        controller: RefreshController,
        openMainWindow: @escaping () -> Void
    ) {
        self.state = state
        self.openMainWindow = openMainWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: PopoverView(
                state: state,
                controller: controller,
                openMainWindow: { [weak self] in
                    self?.closePopover()
                    openMainWindow()
                },
                refresh: { Task { await controller.refresh() } },
                quit: { NSApp.terminate(nil) }
            )
        )
        // Let the popover follow the content's own height rather than fixing
        // it, so a short list does not sit above a slab of empty space.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        updateTitle()
        observeState()
    }

    // MARK: - Title

    private func updateTitle() {
        guard let button = statusItem.button else { return }

        let segments = StatusBarTitleBuilder.segments(
            pullRequests: state.visiblePullRequests.count,
            mentions: state.visibleNotifications.count,
            issues: state.visibleIssues.count,
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
                let offset = SymbolAlignment.inkExtent(of: image).map {
                    SymbolAlignment.baselineOffset(
                        imageHeight: image.size.height,
                        inkTop: $0.top,
                        inkBottom: $0.bottom,
                        capHeight: font.capHeight
                    )
                } ?? 0
                attachment.bounds = CGRect(
                    x: 0, y: offset, width: image.size.width, height: image.size.height
                )
                title.append(NSAttributedString(attachment: attachment))
            }
        }

        button.attributedTitle = title
        button.toolTip = StatusBarTitleBuilder.accessibilityLabel(
            pullRequests: state.visiblePullRequests.count,
            mentions: state.visibleNotifications.count,
            issues: state.visibleIssues.count,
            health: state.health
        )
    }

    /// `@Observable` has no publisher, so we re-arm the tracking closure after
    /// every change.
    private func observeState() {
        withObservationTracking {
            _ = state.visiblePullRequests.count
            _ = state.visibleNotifications.count
            _ = state.visibleIssues.count
            _ = state.hasToken
            _ = state.loadState
            _ = state.settings.statusBarStyle
            _ = state.settings.includeDrafts
            _ = state.settings.repositoryFilters
            _ = state.settings.notificationReasons
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
