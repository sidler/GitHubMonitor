import AppKit
import GitHubMonitorKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Start as a menu bar agent: no Dock icon until a window is opened.
//
// Done here rather than with LSUIElement in Info.plist on purpose. That flag
// prevents the menu bar from being set up at all, and a later switch to a
// regular policy then shows menu titles that do not open.
application.setActivationPolicy(.accessory)
application.run()
