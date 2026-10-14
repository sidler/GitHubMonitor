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
    /// The least the list column may be squeezed to. Named because the
    /// detail pane's ceiling is worked out from it.
    private static let listMinimumWidth: CGFloat = 420

    /// Whether a recalculation of the detail pane's ceiling is already
    /// waiting for the drag to end. Every step of a drag asks for one.
    private var isCapScheduled = false

    private var inspectorItem: NSSplitViewItem?
    private var contentController: NSViewController?
    /// The diff put up over the whole window, while one is open.
    private var diffOverlay: DiffOverlayView<DiffOverlay>?
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
        } else {
            observeScrolling()
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
        // Which column gives way when the window changes size, said out
        // loud. The lowest holding priority is the first to be taken from
        // and the first to be given to; left at the default all three are
        // equal, and then it is the layout engine's business which one
        // yields. The sidebar holds hardest: it is the one column the
        // window was asked to keep a width for, and with a ceiling of 320
        // it cannot usefully absorb anything anyway.
        //
        // This is about resizing only. Where a *drag* stops is a separate
        // matter, and `ColumnsController` is where that is settled.
        sidebar.holdingPriority = .defaultLow + 10
        split.addSplitViewItem(sidebar)
        sidebarItem = sidebar

        let contentController = NSHostingController(
            rootView: ContentColumn(state: state, controller: controller)
        )
        // What this column publishes to Auto Layout is how small it can
        // be, not how wide it would like to be. The default is the
        // latter, and the detail pane's ceiling is worked out from the
        // former: with the wrong one in hand the ceiling allowed a drag
        // forty points further than the column could actually go, and
        // AppKit took those forty from the sidebar.
        contentController.sizingOptions = [.minSize]
        let content = NSSplitViewItem(viewController: contentController)
        content.minimumThickness = Self.listMinimumWidth
        // The middle is the room. It takes what a wider window brings and
        // gives up what the panes beside it ask for, down to its own
        // minimum and no further -- which is where a drag stops.
        content.holdingPriority = .defaultLow
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
    /// the detail pane, which is narrow and can be dragged narrower.
    private func syncDiffOverlay() {
        guard let split = splitViewController?.view else { return }

        guard let opened = state.openedDiff else {
            guard let overlay = diffOverlay else { return }
            overlay.removeFromSuperview()
            diffOverlay = nil
            if let previous = responderBeforeDiff { window?.makeFirstResponder(previous) }
            responderBeforeDiff = nil
            // Nothing of the last approval outlives the overlay. A question
            // left unanswered -- the check came back after someone pressed
            // Escape -- would otherwise raise itself unprompted the next
            // time a diff was opened, one Return from approving.
            if !state.approval.isBusy { state.approval = .idle }
            return
        }

        // Already up: hand it the current state rather than leaving it with
        // the one it was built from, or a refusal would never reach it.
        if let overlay = diffOverlay {
            overlay.rootView = overlayContent(opened)
            return
        }

        let view = DiffOverlayView(rootView: overlayContent(opened))
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

    /// What the overlay's own panel shows: the pull request being read and
    /// the issues it answers.
    ///
    /// Built from what is already held rather than fetched. The detail is
    /// loaded beside the diff, so by the time anybody asks, the description
    /// is usually there -- and where it is not, the panel says the heading
    /// facts and fills in.
    private func subject(for item: PullRequestItem) -> LinkedSubject {
        var detail: PullRequestDetail?
        if case .loaded(let loaded) = state.pullRequestDetails[item.id] { detail = loaded }
        return LinkedSubject(
            context: LinkedPanelContext(state: state, controller: controller),
            summary: .local(item, detail: detail),
            links: state.links(of: item),
            unshown: state.unshownLinks(of: item)
        )
    }

    private func overlayContent(_ opened: OpenedDiff) -> DiffOverlay {
        let item = state.pullRequest(withID: opened.pullRequestID)
        return DiffOverlay(
            files: opened.files,
            pullRequest: opened.url,
            startingPath: opened.path,
            startingSidebarWidth: state.settings.diffSidebarWidth,
            setSidebarWidth: { [state] width in state.settings.diffSidebarWidth = width },
            close: { [weak state] in state?.openedDiff = nil },
            review: item.map(reviewActions(for:)),
            subject: item.map(subject(for:)),
            fontSize: state.settings.diffFontSize,
            showsLineNumbers: state.settings.showsDiffLineNumbers,
            layout: state.settings.diffLayout,
            threads: state.reviewThreads[opened.pullRequestID] ?? [],
            setLayout: { [state] in state.settings.diffLayout = $0 },
            viewed: ViewedFiles(
                app: state,
                pullRequestID: opened.pullRequestID,
                toggle: { [controller, state] path in
                    let now = state.viewedState(of: path, in: opened.pullRequestID)
                    // A file GitHub has dismissed is unticked as far as the
                    // tick goes, so pressing it ticks it -- which is what
                    // somebody who has just re-read it means.
                    controller.setViewed(
                        now != .viewed, path: path, in: opened.pullRequestID
                    )
                }
            ),
            draft: state.reviewDrafts[opened.pullRequestID],
            // Only where there is a pull request to write about. A diff
            // opened for something that has since left the lists can be
            // read; it cannot be reviewed.
            writing: item.map { item in
                DraftWriting(
                    add: { [controller] path, line, side, body in
                        controller.addRemark(
                            to: item, path: path, line: line, side: side, body: body
                        )
                    },
                    change: { [controller] id, body in
                        controller.changeRemark(id, in: item.id, to: body)
                    },
                    remove: { [controller] id in
                        controller.removeRemark(id, in: item.id)
                    }
                )
            }
        )
    }

    /// What the overlay may do with this pull request, and how.
    private func reviewActions(for item: PullRequestItem) -> ReviewActions {
        ReviewActions(
            title: item.title,
            repository: item.repository,
            number: item.number,
            didAuthor: item.viewerDidAuthor,
            viewerState: item.viewerReview?.state,
            isAutoMergeArmed: item.isAutoMergeArmed,
            isBusy: state.approval.isBusy,
            isConfirming: state.approval.isConfirming(item.id),
            failure: state.approval.message(for: item.id),
            ask: { [controller] in await controller.askToApprove(item) },
            cancel: { [controller] in controller.cancelApproval() },
            approve: { [controller] in await controller.approve(item) }
        )
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
        scheduleInspectorCap()
    }

    /// Works the ceiling out again once the pointer has been let go.
    ///
    /// Not now: this is called from inside AppKit's own drag tracking, and
    /// a constraint changed there left the list column drawn in the wrong
    /// place -- white down one side, under the detail pane on the other.
    /// The run loop is in a tracking mode for as long as the button is
    /// down, so asking for the default mode is asking for afterwards.
    ///
    /// Nothing is lost by waiting. What the ceiling is made of -- the
    /// window's width and the sidebar's -- cannot change while the
    /// detail pane's own divider is being dragged.
    private func scheduleInspectorCap() {
        guard !isCapScheduled else { return }
        isCapScheduled = true
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isCapScheduled = false
                self.capInspectorWidth()
            }
        }
    }

    /// How wide the detail pane may be drawn before it would start taking
    /// room from the sidebar.
    ///
    /// NSSplitView, asked to pull a divider past what the pane beside it
    /// can give, pushes the divider behind it rather than stopping. So
    /// pulling the detail pane wide went through the list column and on
    /// into the sidebar, which snapped back to its own minimum and cut off
    /// the names it had been widened to show. The sidebar is not part of
    /// the conversation between those two columns and should not be moved
    /// by it.
    ///
    /// A ceiling worked out from what is on screen, rather than a limit on
    /// the drag itself: the delegate methods that constrain a divider are
    /// refused by NSSplitViewController, which lays out with constraints
    /// of its own -- it says so and throws at launch rather than quietly
    /// ignoring them. Holding priorities are no use either; AppKit's own
    /// header says they must stay below the priority a divider is dragged
    /// at, which is to say below the thing they would have to outrank.
    ///
    /// Always reached through `scheduleInspectorCap`, which keeps it out
    /// of the middle of a drag.
    private func capInspectorWidth() {
        guard let inspectorItem, let split = splitViewController else { return }
        let sidebarWidth: CGFloat = sidebarItem.map { item in
            guard !item.isCollapsed else { return 0 }
            // Before the first layout the view has no width yet, and a
            // zero there would hand the detail pane the sidebar's room as
            // though it were free.
            let drawn = item.viewController.view.frame.width
            return drawn > 0 ? drawn : item.minimumThickness
        } ?? 0
        let dividers = split.splitView.dividerThickness * CGFloat(max(0, split.splitViewItems.count - 1))
        // How small the list column can really be, which is not the same
        // as the number set on it: its own contents -- the counts along
        // the bottom, the title and the controls above -- stop being able
        // to give at some width of their own, and AppKit takes the
        // difference from the sidebar if the ceiling does not know about
        // it. The column publishes that width because its hosting
        // controller is set to report its minimum size.
        let listFloor = max(Self.listMinimumWidth, contentController?.view.fittingSize.width ?? 0)
        let room = split.splitView.bounds.width - dividers - sidebarWidth - listFloor
        // Never below its own floor: if the window is too narrow for all
        // three at once, that is a fight between the minimums and not
        // something a ceiling should join in on.
        let ceiling = max(inspectorItem.minimumThickness, room)
        // Only on a change. Setting this lays the split view out again,
        // which is what called this in the first place.
        if inspectorItem.maximumThickness != ceiling {
            inspectorItem.maximumThickness = ceiling
        }
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
    /// Watches the content for scrolling, from scratch.
    ///
    /// Called when the window is built and again whenever it is shown,
    /// because closing it takes the observer away while keeping the window
    /// itself -- so `show()` found a window already there, skipped
    /// building one, and the reopened window never watched anything again.
    /// The band behind the title then stayed as it was, and rows scrolled
    /// straight through it.
    private func observeScrolling() {
        NotificationCenter.default.removeObserver(
            self, name: NSView.boundsDidChangeNotification, object: nil
        )
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

    /// Adds or removes the controls item, following whether the view on
    /// screen has any controls to put there.
    ///
    /// Leaving an empty item in place is not free: every toolbar item gets
    /// its own glass background, so one hosting nothing shows as a sliver of
    /// glass beside the title.
    private func syncToolbarControls() {
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

    /// Re-sizes the toolbar item that hosts SwiftUI views.
    ///
    /// A view-based toolbar item keeps the width it was given when the
    /// toolbar last laid out, and a new list brings different controls with
    /// it. Without this, coming back from a list with no controls left them
    /// running off the window's edge until it was resized.
    private func resizeToolbarItems() {
        var total: CGFloat = 0
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
            _ = state.approval
            _ = state.merging
            // A remark written into the diff has to appear in it, and the
            // overlay is rebuilt rather than mutated.
            _ = state.reviewDrafts
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
            // Changed from the View menu while a diff is on screen, which is
            // the only sensible moment to change it: the overlay is rebuilt
            // rather than left at the size it was opened with.
            _ = state.settings.diffFontSize
            _ = state.settings.showsDiffLineNumbers
            _ = state.settings.diffLayout
            // The diff is open before the comments arrive, so it has to be
            // rebuilt when they do.
            _ = state.reviewThreads
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
        // A floor but no ceiling. The pane holds a description, a
        // conversation and a list of files, all of which read better
        // wider, and on a large screen there is room to spare -- the cap
        // of four hundred points was a guess about how much anybody would
        // want, which is not a thing to guess about. The drag stops on its
        // own when the content column reaches its own minimum.
        //
        // Both ends have to be said out loud. An inspector item arrives
        // with its thickness fixed and, in AppKit's own words, is "not
        // resizable by default": leaving the maximum alone does not mean
        // no maximum, it means the 270 it came with. Dropping the line
        // that said 400 therefore made the pane narrower-minded, not
        // wider -- a maximum below the minimum is a pane nailed to one
        // width. Unspecified is what no ceiling is actually called.
        //
        // The floor is where the pane opens, since nothing else now says
        // how wide it should start: four hundred, the width it has always
        // had. It is also as narrow as it goes, which is the one thing
        // this trade costs.
        newItem.minimumThickness = 400
        // No ceiling of its own -- `capInspectorWidth` puts one there and
        // keeps moving it, since how wide this may be is a question about
        // the window rather than about the pane. It has to be said out
        // loud all the same: an inspector item arrives with its thickness
        // fixed and, in AppKit's own words, is "not resizable by
        // default", so leaving the maximum alone does not mean no maximum,
        // it means the 270 it came with.
        newItem.maximumThickness = NSSplitViewItem.unspecifiedDimension
        // Between the sidebar and the middle: a wider window should not
        // quietly undo the width a drag set here, but if something has to
        // give it is still not the sidebar.
        newItem.holdingPriority = .defaultLow + 5
        // The pane is put up and taken away by the app -- the item is
        // added when a row is inspected and removed when none is -- so it
        // should not also shut under the pointer. That would be a second
        // state the rest of the code knows nothing about. The drag stops
        // where the content column needs the room instead.
        newItem.canCollapse = false
        split.addSplitViewItem(newItem)
        inspectorItem = newItem
        syncInspectorSeparator()
        ensureRoomForInspector()
        capInspectorWidth()
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
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
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
