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
    }
}
