import AppKit
import GitHubMonitorKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Menu bar agent: no Dock icon. Matches LSUIElement in Info.plist and keeps
// the app well behaved when launched straight from the build directory.
application.setActivationPolicy(.accessory)
application.run()
