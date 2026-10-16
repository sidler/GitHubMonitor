import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var mainWindowController: MainWindowController?
    private var refreshController: RefreshController?
    private let state = AppState(settings: Settings())

    public override init() {
        super.init()
    }

    /// Development switches, accepted both as environment variables and as
    /// launch arguments. `open` forwards arguments but not the environment,
    /// and launching through `open` matters because a process started as a
    /// child of a shell is attributed to that shell by tools like Little
    /// Snitch.
    private func devOption(_ name: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[name] { return value }
        let flag = "--\(name.lowercased().replacingOccurrences(of: "ghm_", with: ""))"
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        // A bare flag means "on"; a following value overrides it.
        let next = arguments.index(after: index)
        guard next < arguments.endIndex, !arguments[next].hasPrefix("--") else { return "1" }
        return arguments[next]
    }

    /// How long the pointer has to rest before a tooltip appears, in
    /// milliseconds.
    ///
    /// The system waits far longer, which is right for a word processor and
    /// wrong for a row of status symbols: every one of them has a tooltip
    /// that is the only place its meaning is written down, and waiting out
    /// the system delay for each is how somebody stops asking.
    ///
    /// Registered rather than written: this is a default AppKit reads on
    /// the way past, and the app has no business leaving it in the user's
    /// own preferences.
    static let toolTipDelay = 300

    public func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": Self.toolTipDelay])

        let refresh = RefreshController(state: state)
        refreshController = refresh

        let windowController = MainWindowController(state: state, controller: refresh)
        mainWindowController = windowController
        statusItemController = StatusItemController(
            state: state,
            controller: refresh,
            openMainWindow: { windowController.show() }
        )

        // A real menu, so the standard shortcuts are where macOS expects
        // them and text fields get working copy and paste.
        NSApp.mainMenu = AppMenu.build(
            appName: "GitHub Monitor",
            openSettings: { windowController.show(selecting: .settings) },
            refresh: { Task { await refresh.refreshShown() } },
            moveDetail: { refresh.moveInspection(by: $0) },
            closeDetail: { refresh.closeInspector() },
            changeDiffFontSize: { [state] step in state.settings.changeDiffFontSize(by: step) },
            resetDiffFontSize: { [state] in state.settings.resetDiffFontSize() },
            showsDiffLineNumbers: { [state] in state.settings.showsDiffLineNumbers },
            toggleDiffLineNumbers: { [state] in
                state.settings.showsDiffLineNumbers.toggle()
            },
            diffLayout: { [state] in state.settings.diffLayout },
            setDiffLayout: { [state] layout in state.settings.diffLayout = layout },
            diffPaging: { [state] in state.settings.diffPaging },
            setDiffPaging: { [state] paging in state.settings.diffPaging = paging },
            stepDiffFile: { step in
                NotificationCenter.default.post(
                    name: .diffStepFile, object: nil, userInfo: ["step": step]
                )
            },
            canStepDiffFile: { [state] in
                // Only with a diff open, and not while somebody is
                // typing: a disabled item hands its key equivalent back,
                // so option-left goes on being word-left in the box where
                // a review remark is written.
                guard state.openedDiff != nil else { return false }
                return !(NSApp.keyWindow?.firstResponder is NSTextView)
            }
        )

        // Sample data is opt-in now that real requests work, so the UI can
        // still be exercised without a token.
        if devOption("GHM_SAMPLE") != nil {
            state.isBigSample = devOption("GHM_BIG") != nil
            state.loadSampleData()
            // Development aid: what the menu bar does when a refresh fails
            // on top of counts that already arrived. Applied after the
            // sample load, which marks itself loaded.
            if let message = devOption("GHM_FAIL") {
                state.loadState = .failed(
                    message == "1" ? "The request timed out." : message
                )
            }
        } else {
            Task {
                // Without a token there is nothing to show and nowhere to go,
                // so put the user in front of the token field straight away.
                if await refresh.start() == false {
                    windowController.show(selecting: .settings)
                }
            }
        }

        // Development aid: draws the app in one theme whatever the Mac is
        // set to, so both can be looked at without changing a system-wide
        // preference. Checking a colour against the ground it lands on is
        // the reason this exists.
        if let theme = devOption("GHM_THEME") {
            NSApp.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        }

        // Development aid: opens the detail pane for the first row of
        // whichever list is on screen, so the pane can be inspected without
        // a click.
        // `--inspect 482` opens that one; a bare `--inspect` opens the
        // first row of whichever list is on screen.
        if let wanted = devOption("GHM_INSPECT") {
            Task { [weak self] in
                for _ in 0..<40 {
                    guard let self else { return }
                    if let list = state.selectedList {
                        switch list.content {
                        case .pullRequests:
                            let rows = state.pullRequests(in: list)
                            if let first = rows.first(where: { "\($0.number)" == wanted })
                                ?? rows.first {
                                refresh.inspect(first)
                                return
                            }
                        case .issues:
                            let rows = state.issues(in: list)
                            if let first = rows.first(where: { "\($0.number)" == wanted })
                                ?? rows.first {
                                refresh.inspect(first)
                                return
                            }
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }

        // Development aid: opens a diff without a hand on the mouse.
        //
        // It picks the pull request the sample actually carries a patch
        // for rather than whichever row happens to be first, and prefers
        // one somebody left a conversation on -- the threads are drawn in
        // the diff and nowhere else, so that is what this exists to look
        // at. In a real account the patch arrives only after a row is
        // inspected, so there this lands on whatever has been opened
        // already; the sample seeds it, which is the case this is for.
        if let wanted = devOption("GHM_DIFF") {
            Task { [weak self] in
                for _ in 0..<60 {
                    guard let self else { return }
                    let talked = Set(state.reviewThreads.filter { !$0.value.isEmpty }.keys)
                    let ready = state.changedFiles
                        .compactMap { id, files -> (String, [ChangedFile])? in
                            guard case .loaded(let loaded) = files, !loaded.isEmpty else { return nil }
                            return (id, loaded)
                        }
                        .sorted { talked.contains($0.0) && !talked.contains($1.0) }

                    if let (id, files) = ready.first,
                        let item = state.allPullRequests.first(where: { $0.id == id }) {
                        refresh.inspect(item)
                        refresh.loadReviewThreadsIfNeeded(for: id)
                        // A turn of the run loop before the overlay goes
                        // up. Inspecting rebuilds the detail pane, and
                        // the overlay set in the same breath was gone
                        // again by the time anything looked.
                        try? await Task.sleep(for: .milliseconds(600))
                        guard let item = state.allPullRequests.first(where: { $0.id == id })
                        else { return }
                        // `--diff SessionFilter` opens that file; a bare
                        // `--diff` opens whichever one carries the first
                        // conversation.
                        let here = state.reviewThreads[id]?.first?.path
                        let file = files.first { $0.path.contains(wanted) }
                            ?? files.first { $0.path == here }
                            ?? files[0]
                        state.openedDiff = OpenedDiff(
                            pullRequestID: id, path: file.path, files: files, url: item.url
                        )
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }

        // Development aid: lets the window and popover be opened without a
        // mouse click, e.g. for screenshots during a build.
        if let tab = devOption("GHM_OPEN") {
            // The status item has no window to anchor a popover to until the
            // first pass through the run loop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                switch tab {
                case "popover":
                    self?.statusItemController?.showPopover(activating: true)
                default:
                    // "settings:general" opens a specific settings tab.
                    let parts = tab.split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2, let settingsTab = SettingsTab(rawValue: parts[1]) {
                        self?.state.selectedSettingsTab = settingsTab
                    }
                    windowController.show(selecting: MainWindowTab(name: parts[0]))
                }
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        refreshController?.stop()
    }
}
