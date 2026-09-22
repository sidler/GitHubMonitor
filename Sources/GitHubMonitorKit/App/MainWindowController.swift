import AppKit
import Observation
import SwiftUI

/// The optional full view: complete lists, previews and settings.
///
/// Built from an `NSSplitViewController` rather than a SwiftUI
/// `NavigationSplitView`. Only a real sidebar split view item, together with
/// the toolbar's sidebar tracking separator, makes AppKit line the toolbar's
/// own divider up with the split below it; hosting a SwiftUI split view in a
/// plain window leaves the two three points apart, which shows as a step in
/// the vertical line.
///
/// While this window is open the app switches to a regular activation policy,
/// so it appears in the Dock and the app switcher and its menu bar is shown.
/// Closing the window drops back to an accessory.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let state: AppState
    private let controller: RefreshController
    private var window: NSWindow?
    private var splitViewController: NSSplitViewController?
    private var inspectorItem: NSSplitViewItem?
    private var contentController: NSViewController?
    /// The selection the window last reacted to, so a change can be told
    /// from the other state the tracking closure watches.
    private var lastSelection: SidebarSelection?
    /// Width constraints on the toolbar's hosted views, kept so each one can
    /// be updated rather than stacking a new constraint on every switch.
    private var toolbarWidths: [NSToolbarItem.Identifier: NSLayoutConstraint] = [:]

    public init(state: AppState, controller: RefreshController) {
        self.state = state
        self.controller = controller
        super.init()
    }

    public func show(selecting tab: MainWindowTab? = nil) {
        switch tab {
        case .list(let name):
            // By id first, then by title: the development hook and the menu
            // both name lists the way a person would.
            let match = state.lists.first { $0.id == name }
                ?? state.lists.first { $0.title.caseInsensitiveCompare(name) == .orderedSame }
            if let match {
                state.sidebarSelection = .list(id: match.id, repository: nil)
            }
        case .mentions: state.sidebarSelection = .mentions(repository: nil)
        case .dashboard: state.sidebarSelection = .dashboard
        case .trends: state.sidebarSelection = .trends
        case .myTrends: state.sidebarSelection = .myTrends
        case .settings: state.sidebarSelection = .settings
        case nil: break
        }
        state.normaliseSelection()

        if window == nil {
            makeWindow()
        }

        // Becoming a regular app is what puts the window in the app switcher
        // and shows the menu bar; it has to happen before activating.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // Development aid: report the window number so screenshots can be
        // taken with `screencapture -l` instead of guessing at crop rects.
        if ProcessInfo.processInfo.environment["GHM_TRACE_FRAME"] != nil, let window {
            let screenHeight = window.screen?.frame.height ?? 0
            let frame = window.frame
            FileHandle.standardError.write(
                "WINDOW \(window.windowNumber) centre \(Int(frame.midX)) \(Int(screenHeight - frame.midY))\n"
                    .data(using: .utf8)!
            )
        }
    }

    // MARK: - Construction

    private func makeWindow() {
        let split = NSSplitViewController()

        let sidebar = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: SidebarColumn(state: state))
        )
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 320
        split.addSplitViewItem(sidebar)

        let contentController = NSHostingController(
            rootView: ContentColumn(state: state, controller: controller)
        )
        let content = NSSplitViewItem(viewController: contentController)
        content.minimumThickness = 420
        split.addSplitViewItem(content)
        self.contentController = contentController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = split
        window.delegate = self
        window.isReleasedWhenClosed = false
        // Compact: the regular height leaves a band of empty space above the
        // content for a title that needs a fraction of it.
        window.toolbarStyle = .unifiedCompact
        // Transparent, so each column's own background shows through the
        // title bar band — that is what makes the divider continuous, as in
        // Notes and Finder. The split view's safe area keeps scrolling
        // content from running under the toolbar.
        window.titlebarAppearsTransparent = true

        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.setContentSize(NSSize(width: 1060, height: 680))
        window.center()

        self.window = window
        splitViewController = split
        lastSelection = state.sidebarSelection

        updateTitle()
        syncToolbarControls()
        observeSelection()
        observeScrolling()
        // Something can already be open when the window is first built --
        // the popover selects as it loads -- and the tracking closure only
        // fires on the next change after that.
        syncInspector()
    }

    // MARK: - Scrolling

    /// Watches the content column's scroll view so the title bar band knows
    /// when rows are passing behind it.
    ///
    /// SwiftUI's `onScrollGeometryChange` does not fire for a `List`, which
    /// on macOS is an NSTableView inside an NSScrollView rather than a
    /// SwiftUI scroll view. Observing the clip view directly works for every
    /// list, and survives switching between them because the notification is
    /// matched by ancestry rather than by a stored object.
    private func observeScrolling() {
        // A selector rather than a closure: Swift 6 will not let a
        // Notification cross into the main actor from a sendable closure,
        // and bounds changes are posted on the main thread anyway.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: nil
        )
    }

    @objc private func contentDidScroll(_ notification: Notification) {
        guard
            let clipView = notification.object as? NSClipView,
            let contentView = contentController?.view,
            clipView.isDescendant(of: contentView)
        else { return }

        let inset = clipView.enclosingScrollView?.contentInsets.top ?? 0
        let scrolled = clipView.bounds.origin.y + inset > 1
        if state.isContentScrolled != scrolled {
            state.isContentScrolled = scrolled
        }
    }

    // MARK: - Title

    /// The window title is the list's name, and the section it belongs to is
    /// the subtitle -- which AppKit draws in the unified toolbar, the native
    /// equivalent of SwiftUI's navigationTitle.
    ///
    /// Drawn by AppKit again. It used to be a hosted SwiftUI view, because
    /// the native title sat hard against the sidebar divider where Notes and
    /// Mail inset theirs; macOS 26 insets it properly, and a hosted view in
    /// a toolbar now comes with the glass background that belongs to
    /// controls, which made a plain title look like a button.
    private func updateTitle() {
        window?.title = state.selectionTitle
        window?.subtitle = state.selectionSubtitle
        window?.titleVisibility = .visible
    }

    /// Resets what belongs to the list being left behind.
    private func selectionDidChange() {
        guard lastSelection != state.sidebarSelection else { return }
        lastSelection = state.sidebarSelection
        // A list that has just appeared sits at its top, so the band over the
        // title bar should be clear again. One that restores a scroll
        // position posts its own bounds change and turns it back on.
        state.isContentScrolled = false
        syncToolbarControls()
        // After SwiftUI has redrawn the toolbar's own views; their new sizes
        // do not exist yet at this point.
        DispatchQueue.main.async { [weak self] in self?.resizeToolbarItems() }
    }

    /// Adds or removes the controls item, following whether the view on
    /// screen has any controls to put there.
    ///
    /// Leaving an empty item in place is not free: every toolbar item gets
    /// its own glass background, so one hosting nothing shows as a sliver of
    /// glass beside the title.
    private func syncToolbarControls() {
        guard let toolbar = window?.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.controlsItem }

        if state.sidebarSelection.hasToolbarControls {
            guard index == nil else { return }
            // Before the inspector's separator, which is what holds the
            // controls over the list rather than over the detail pane.
            let separator = toolbar.items.firstIndex {
                $0.itemIdentifier == .inspectorTrackingSeparator
            }
            toolbar.insertItem(
                withItemIdentifier: Self.controlsItem,
                at: separator ?? toolbar.items.count
            )
        } else if let index {
            toolbar.removeItem(at: index)
            // The item is rebuilt from scratch when it comes back, so the
            // constraint measured for the old one must not outlive it.
            toolbarWidths[Self.controlsItem] = nil
        }
    }

    /// Re-sizes the toolbar item that hosts SwiftUI views.
    ///
    /// A view-based toolbar item keeps the width it was given when the
    /// toolbar last laid out, and a new list brings different controls with
    /// it. Without this, coming back from a list with no controls left them
    /// running off the window's edge until it was resized.
    private func resizeToolbarItems() {
        for item in window?.toolbar?.items ?? [] {
            guard item.itemIdentifier == Self.controlsItem, let view = item.view
            else { continue }

            view.invalidateIntrinsicContentSize()
            view.layoutSubtreeIfNeeded()
            // The intrinsic size rather than the fitting one: the fitting
            // size solves the constraint set below and would therefore only
            // ever report the width this method last handed out.
            let intrinsic = view.intrinsicContentSize.width
            let width = intrinsic == NSView.noIntrinsicMetric ? view.fittingSize.width : intrinsic

            if let constraint = toolbarWidths[item.itemIdentifier] {
                constraint.constant = width
            } else {
                let constraint = view.widthAnchor.constraint(equalToConstant: width)
                constraint.isActive = true
                toolbarWidths[item.itemIdentifier] = constraint
            }
        }
    }

    /// `@Observable` has no publisher, so the tracking closure re-arms itself.
    private func observeSelection() {
        withObservationTracking {
            _ = state.sidebarSelection
            _ = state.inspectedPullRequestID
            _ = state.inspectedIssueID
            _ = state.expandedNotificationID
            _ = state.pullRequestDetails
            _ = state.issueDetails
            // The workload chart's pane follows a bar rather than a row, and
            // a reload of the chart can take that bar away.
            _ = state.workloadSelection
            _ = state.dashboard
            // A thread marked read disappears, and the pane describing it
            // has to go with it. So does an issue that is no longer assigned.
            _ = state.notifications
            _ = state.listPullRequests
            _ = state.listIssues
            // A list can be renamed, reordered or deleted while the window
            // is open, and the title bar follows it.
            _ = state.settings.savedLists
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.selectionDidChange()
                self.updateTitle()
                self.syncInspector()
                self.observeSelection()
            }
        }
    }

    // MARK: - Inspector

    /// Adds or removes the detail pane as a third column, following the
    /// selection.
    private func syncInspector() {
        guard let split = splitViewController else { return }

        // The lists are bound straight to their selection, so the arrow keys
        // can move it without anything having asked for the payload yet.
        switch state.sidebarSelection {
        case .list:
            switch state.selectedList?.content {
            case .pullRequests:
                if let id = state.inspectedPullRequestID {
                    controller.loadDetailIfNeeded(for: id)
                }
            case .issues:
                if let id = state.inspectedIssueID {
                    controller.loadIssueDetailIfNeeded(for: id)
                }
            case nil:
                break
            }
        case .mentions:
            if let item = state.inspectedNotification {
                controller.loadPreviewIfNeeded(for: item)
            }
        case .dashboard, .trends, .myTrends, .settings:
            break
        }

        guard state.hasInspectorContent else {
            if let inspectorItem {
                split.removeSplitViewItem(inspectorItem)
                self.inspectorItem = nil
                syncInspectorSeparator()
            }
            return
        }

        // Already open: InspectorColumn follows the selection on its own.
        // Swapping the view controller here instead would tear down a hosting
        // view that AppKit still holds tooltip tracking for, and the tooltip
        // manager reads freed memory on the next pointer move.
        guard inspectorItem == nil else { return }

        let hosting = NSHostingController(
            rootView: InspectorColumn(state: state, controller: controller)
        )
        let newItem = NSSplitViewItem(inspectorWithViewController: hosting)
        newItem.minimumThickness = 280
        newItem.maximumThickness = 400
        split.addSplitViewItem(newItem)
        inspectorItem = newItem
        syncInspectorSeparator()
        ensureRoomForInspector()
    }

    /// Keeps the toolbar's inspector separator with the pane it tracks.
    ///
    /// It is what holds the list's controls over the list: with the pane
    /// open they end at its divider rather than floating at the window's
    /// edge above a pane they have nothing to do with. Without a pane it
    /// has no divider to find and would sit at an arbitrary position, so it
    /// is added and removed along with the pane itself.
    private func syncInspectorSeparator() {
        guard let toolbar = window?.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == .inspectorTrackingSeparator }

        if inspectorItem != nil {
            guard index == nil else { return }
            toolbar.insertItem(withItemIdentifier: .inspectorTrackingSeparator, at: toolbar.items.count)
        } else if let index {
            toolbar.removeItem(at: index)
        }
    }

    /// Widens the window when the detail pane opens into one too narrow to
    /// hold three columns, rather than squeezing the list to shreds.
    private func ensureRoomForInspector() {
        guard let window, window.frame.width < Self.widthWithInspector else { return }
        var frame = window.frame
        let available = window.screen?.visibleFrame ?? frame
        frame.size.width = Self.widthWithInspector
        if frame.maxX > available.maxX {
            frame.origin.x = max(available.minX, available.maxX - frame.width)
        }
        window.setFrame(frame, display: true, animate: true)
    }

    private static let widthWithInspector: CGFloat = 1180

    // MARK: - Toolbar

    private static let controlsItem = NSToolbarItem.Identifier("controls")

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.inspectorTrackingSeparator]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // The tracking separator pins the toolbar's divider to the
        // sidebar's, which is the reason this window is built on a split
        // view controller. The inspector's own separator is not here: it
        // comes and goes with the detail pane, since with no pane to track
        // it still takes a position in the toolbar and pushes the controls
        // away from the edge.
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.controlsItem]
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)

        switch identifier {
        case Self.controlsItem:
            let hosting = NSHostingView(rootView: ToolbarControls(state: state, controller: controller))
            hosting.sizingOptions = [.intrinsicContentSize]
            item.view = hosting
            item.visibilityPriority = .high
        default:
            return nil
        }

        return item
    }

    // MARK: - Window lifecycle

    public func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)

        // Back to an agent once the window is gone. Deferred because the
        // window is still closing at this point, and switching policy
        // mid-close leaves the Dock icon behind.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
