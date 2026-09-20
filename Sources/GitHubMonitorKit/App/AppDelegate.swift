import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var mainWindowController: MainWindowController?
    private let state = AppState(settings: Settings())

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Stage 1: sample data until the API clients land.
        state.loadSampleData()

        let windowController = MainWindowController(state: state)
        mainWindowController = windowController
        statusItemController = StatusItemController(
            state: state,
            openMainWindow: { windowController.show() }
        )

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
}
