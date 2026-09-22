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

    public func applicationDidFinishLaunching(_ notification: Notification) {
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
            refresh: { Task { await refresh.refresh() } },
            moveDetail: { refresh.moveInspection(by: $0) },
            closeDetail: { refresh.closeInspector() }
        )

        // Sample data is opt-in now that real requests work, so the UI can
        // still be exercised without a token.
        if devOption("GHM_SAMPLE") != nil {
            state.loadSampleData()
        } else {
            Task {
                // Without a token there is nothing to show and nowhere to go,
                // so put the user in front of the token field straight away.
                if await refresh.start() == false {
                    windowController.show(selecting: .settings)
                }
            }
        }

        // Development aid: opens the detail pane for the first row of
        // whichever list is on screen, so the pane can be inspected without
        // a click.
        if devOption("GHM_INSPECT") != nil {
            Task { [weak self] in
                for _ in 0..<40 {
                    guard let self else { return }
                    if let list = state.selectedList {
                        switch list.content {
                        case .pullRequests:
                            if let first = state.pullRequests(in: list).first {
                                refresh.inspect(first)
                                return
                            }
                        case .issues:
                            if let first = state.issues(in: list).first {
                                refresh.inspect(first)
                                return
                            }
                        }
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
