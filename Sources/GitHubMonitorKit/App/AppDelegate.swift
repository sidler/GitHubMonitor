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
            refresh: { Task { await refresh.refresh() } }
        )

        // Sample data is opt-in now that real requests work, so the UI can
        // still be exercised without a token.
        if devOption("GHM_SAMPLE") != nil {
            state.loadSampleData()
        } else {
            refresh.start()
            // Without a token there is nothing to show and nowhere to go, so
            // put the user in front of the token field straight away.
            if !state.hasToken {
                windowController.show(selecting: .settings)
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
                    windowController.show(selecting: MainWindowTab(rawValue: parts[0]) ?? .pullRequests)
                }
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        refreshController?.stop()
    }
}
