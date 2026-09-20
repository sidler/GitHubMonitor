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

        // Sample data is opt-in now that real requests work, so the UI can
        // still be exercised without a token.
        if ProcessInfo.processInfo.environment["GHM_SAMPLE"] != nil {
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
        if let tab = ProcessInfo.processInfo.environment["GHM_OPEN"] {
            // The status item has no window to anchor a popover to until the
            // first pass through the run loop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                switch tab {
                case "popover": self?.statusItemController?.showPopover(activating: true)
                default: windowController.show(selecting: MainWindowTab(rawValue: tab) ?? .pullRequests)
                }
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        refreshController?.stop()
    }
}
