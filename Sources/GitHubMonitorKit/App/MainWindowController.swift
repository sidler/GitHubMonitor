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
    /// The diff put up over the whole window, while one is open.
    private var diffOverlay: NSView?
    /// Whatever had the keyboard before the overlay took it.
    private weak var responderBeforeDiff: NSResponder?
    /// Kept so the collapse of the sidebar can be read back: the title is
    /// drawn in the content column now, and has to step around the traffic
    /// lights that land on top of it when the sidebar goes away.
    private var sidebarItem: NSSplitViewItem?
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
        focusList()

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
        sidebarItem = sidebar

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
        observeSidebarCollapse()
        // Something can already be open when the window is first built --
        // the popover selects as it loads -- and the tracking closure only
        // fires on the next change after that.
        syncInspector()
    }

    /// Puts the keyboard in the list of rows rather than in the sidebar.
    ///
    /// Without this a freshly opened window answers the arrow keys by moving
    /// the sidebar's own selection, so someone pressing down to walk the
    /// pull requests narrows them to a repository instead. The rows are what
    /// the window is for; the sidebar is reached with Tab.
    ///
    /// Only when the window opens. Taking focus back on every change would
    /// make the sidebar unusable from the keyboard.
    private func focusList() {
        // After a turn of the run loop: SwiftUI has not built the table
        // behind the list yet when the window is first ordered front.
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                let window = self.window,
                let root = self.contentController?.view,
                let table = Self.firstTable(in: root)
            else { return }
            window.makeFirstResponder(table)
        }
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let found = firstTable(in: subview) { return found }
        }
        return nil
    }

    // MARK: - The diff

    /// Puts the diff over the window, or takes it away.
    ///
    /// A view over the split view rather than a sheet: a sheet's dimmed
    /// ground belongs to the system, so clicking beside it does nothing --
    /// and clicking beside something that covers what you were reading is
    /// the ordinary way to put it away. Over the split rather than inside
    /// the detail pane, because the pane is 400 points wide.
    private func syncDiffOverlay() {
        guard let split = splitViewController?.view else { return }

        guard let opened = state.openedDiff, let files = loadedFiles(for: opened) else {
            guard let overlay = diffOverlay else { return }
            overlay.removeFromSuperview()
            diffOverlay = nil
            if let previous = responderBeforeDiff { window?.makeFirstResponder(previous) }
            responderBeforeDiff = nil
            return
        }

        guard diffOverlay == nil else { return }

        let view = DiffOverlayView(rootView: overlayContent(files: files, opened: opened))
        view.onCancel = { [weak state] in state?.openedDiff = nil }
        view.translatesAutoresizingMaskIntoConstraints = false
        split.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            view.topAnchor.constraint(equalTo: split.topAnchor),
            view.bottomAnchor.constraint(equalTo: split.bottomAnchor),
        ])
        diffOverlay = view
        responderBeforeDiff = window?.firstResponder
        window?.makeFirstResponder(view)
    }

    private func overlayContent(files: [ChangedFile], opened: OpenedDiff) -> some View {
        DiffOverlay(
            files: files,
            pullRequest: state.pullRequest(withID: opened.pullRequestID)?.url
                ?? URL(string: "https://github.com")!,
            path: Binding(
                get: { [weak state] in state?.openedDiff?.path },
                set: { [weak state] path in state?.openedDiff?.path = path }
            ),
            close: { [weak state] in state?.openedDiff = nil }
        )
    }

    private func loadedFiles(for opened: OpenedDiff) -> [ChangedFile]? {
        guard case .loaded(let files) = state.changedFiles[opened.pullRequestID], !files.isEmpty
        else { return nil }
        return files
    }

    // MARK: - Sidebar

    /// Follows the sidebar being collapsed, which moves the traffic lights
    /// onto the content column -- and onto the title it draws there.
    ///
    /// The split view's own notification rather than KVO on the item: a
    /// collapse is a resize, and a selector keeps the main actor out of the
    /// sendability argument a closure would start.
    private func observeSidebarCollapse() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitViewDidResize(_:)),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitViewController?.splitView
        )
        syncSidebarCollapse()
    }

    @objc private func splitViewDidResize(_ notification: Notification) {
        syncSidebarCollapse()
    }

    private func syncSidebarCollapse() {
        let collapsed = sidebarItem?.isCollapsed ?? false
        if state.isSidebarCollapsed != collapsed {
            state.isSidebarCollapsed = collapsed
        }
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
    /// the subtitle.
    ///
    /// Set on the window for the places that read it -- the Window menu,
    /// Mission Control, the app switcher -- but not drawn by AppKit: with a
    /// transparent title bar its label is a 500 point wide field that takes
    /// every click in the band and moves the window for none of them, which
    /// left the title bar draggable only over the sidebar. The content
    /// column draws the title itself instead, in a band that does not take
    /// clicks at all, so the whole strip drags the window again.
    ///
    /// A hosted toolbar item was the other way round, and was tried first:
    /// on macOS 26 a view in the toolbar comes with the glass background
    /// that belongs to controls, which made a plain title look like a
    /// button.
    private func updateTitle() {
        window?.title = state.selectionTitle
        window?.subtitle = state.selectionSubtitle
        window?.titleVisibility = .hidden
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

    /// Whether the view on screen can be split at all -- the charts and the
    /// settings cannot, and an empty item would be a sliver of glass.
    private var groupingOptions: [ListGrouping] {
        // Nothing while a diff is over the window: the toolbar is drawn in
        // the title bar, above anything the content view can put up, so a
        // control left there would float on top of the overlay and change
        // the list nobody can see.
        guard state.openedDiff == nil else { return [] }
        switch state.sidebarSelection {
        case .list: return state.selectedList?.content.groupings ?? []
        case .mentions: return ListGrouping.forNotifications
        case .dashboard, .trends, .myTrends, .settings: return []
        }
    }

    /// Adds or removes the controls item, following whether the view on
    /// screen has any controls to put there.
    ///
    /// Leaving an empty item in place is not free: every toolbar item gets
    /// its own glass background, so one hosting nothing shows as a sliver of
    /// glass beside the title.
    private func syncToolbarControls() {
        syncGroupingItem()

        guard let toolbar = window?.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.controlsItem }

        if state.sidebarSelection.hasToolbarControls, state.openedDiff == nil {
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

    /// Adds or removes the grouping item, following whether the view on
    /// screen can be split at all. The picker inside it follows the list by
    /// itself.
    private func syncGroupingItem() {
        guard let toolbar = window?.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.groupingItem }

        if groupingOptions.isEmpty {
            if let index { toolbar.removeItem(at: index) }
        } else if index == nil {
            // Before the controls, which is where the delegate's own order
            // puts it too -- and failing that before the inspector's
            // separator rather than at the end. Both items are taken away
            // while a diff covers the window, and putting them back leaves
            // neither for the other to aim at: the grouping went past the
            // separator, the controls landed in front of it, and the two
            // came back the wrong way round.
            let position = toolbar.items.firstIndex { $0.itemIdentifier == Self.controlsItem }
                ?? toolbar.items.firstIndex { $0.itemIdentifier == .inspectorTrackingSeparator }
            toolbar.insertItem(
                withItemIdentifier: Self.groupingItem,
                at: position ?? toolbar.items.count
            )
        }
    }

    /// Re-sizes the toolbar item that hosts SwiftUI views.
    ///
    /// A view-based toolbar item keeps the width it was given when the
    /// toolbar last laid out, and a new list brings different controls with
    /// it. Without this, coming back from a list with no controls left them
    /// running off the window's edge until it was resized.
    private func resizeToolbarItems() {
        var total: CGFloat = 0
        for item in window?.toolbar?.items ?? [] {
            guard item.itemIdentifier == Self.controlsItem
                    || item.itemIdentifier == Self.groupingItem,
                  let view = item.view
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
            total += width + Self.toolbarItemGap
        }
        state.toolbarControlsWidth = total
    }

    /// What the system leaves between two toolbar items, measured from the
    /// gap between the grouping switch and the menus beside it.
    private static let toolbarItemGap: CGFloat = 12

    /// `@Observable` has no publisher, so the tracking closure re-arms itself.
    private func observeSelection() {
        withObservationTracking {
            _ = state.sidebarSelection
            _ = state.inspectedPullRequestID
            _ = state.inspectedIssueID
            _ = state.inspectedNotificationID
            _ = state.openedDiff
            // The overlay is opened from a row that already has the files,
            // but a reload can replace them underneath it.
            _ = state.changedFiles
            _ = state.pullRequestDetails
            _ = state.issueDetails
            _ = state.notificationThreads
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
                self.syncDiffOverlay()
                self.syncToolbarControls()
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
                controller.loadThreadIfNeeded(for: item)
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
    private static let groupingItem = NSToolbarItem.Identifier("grouping")

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
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            Self.groupingItem,
            Self.controlsItem,
        ]
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)

        switch identifier {
        case Self.groupingItem:
            let hosting = NSHostingView(rootView: ToolbarGroupingPicker(state: state))
            hosting.sizingOptions = [.intrinsicContentSize]
            item.view = hosting
            item.visibilityPriority = .high
            return item
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

/// Hosts the diff overlay, and stops Escape at it.
///
/// Without this the key travels on up the responder chain to the list
/// underneath, which answers it by closing the detail pane -- so one press
/// put away two things, and the diff took the pane behind it with it.
private final class DiffOverlayView<Content: View>: NSHostingView<Content> {
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("not loaded from a nib")
    }
}
}
