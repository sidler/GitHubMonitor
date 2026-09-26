import AppKit

/// The application's main menu.
///
/// A menu bar agent normally has no menu at all. This app builds one because
/// its window is meant to behave like an ordinary application window: the
/// standard shortcuts (Cmd+, Cmd+W, Cmd+Q) belong to menu items, and the Edit
/// menu is what makes copy and paste work in the token field.
@MainActor
enum AppMenu {
    static func build(
        appName: String,
        openSettings: @escaping () -> Void,
        refresh: @escaping () -> Void,
        moveDetail: @escaping (Int) -> Void,
        closeDetail: @escaping () -> Void
    ) -> NSMenu {
        let main = NSMenu()

        main.addItem(applicationMenu(appName: appName, openSettings: openSettings))
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(viewMenu(refresh: refresh, moveDetail: moveDetail, closeDetail: closeDetail))
        main.addItem(windowMenu())

        return main
    }

    // MARK: - Menus

    private static func applicationMenu(
        appName: String,
        openSettings: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)

        menu.addItem(ActionItem(title: "About \(appName)", keyEquivalent: "") {
            NSApp.orderFrontStandardAboutPanel(options: AboutPanel.options())
        })
        menu.addItem(.separator())

        // The native home for Cmd+, replacing the event monitor.
        let settings = ActionItem(title: "Settings…", keyEquivalent: ",", action: openSettings)
        menu.addItem(settings)
        menu.addItem(.separator())

        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        NSApp.servicesMenu = services
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.submenu = menu
        return item
    }

    private static func fileMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")
        menu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        item.submenu = menu
        return item
    }

    /// Without this menu, Cmd+C and Cmd+V do nothing in text fields.
    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        item.submenu = menu
        return item
    }

    private static func viewMenu(
        refresh: @escaping () -> Void,
        moveDetail: @escaping (Int) -> Void,
        closeDetail: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")
        menu.addItem(ActionItem(title: "Refresh", keyEquivalent: "r", action: refresh))
        menu.addItem(.separator())

        // The list moves the detail pane with the plain arrow keys while it
        // has focus. These do the same from anywhere in the window, and are
        // where someone looks to find out that it can be done at all.
        // Named for the list rather than for pull requests: the mentions
        // move the same way.
        let next = ActionItem(
            title: "Next in List",
            keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            action: { moveDetail(1) }
        )
        next.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(next)

        let previous = ActionItem(
            title: "Previous in List",
            keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            action: { moveDetail(-1) }
        )
        previous.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(previous)

        let close = ActionItem(title: "Close Details", keyEquivalent: "i", action: closeDetail)
        close.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(close)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Toggle Sidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s"
        )
        item.submenu = menu
        return item
    }

    private static func windowMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")
        menu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }
}

/// A menu item that runs a closure, since the standard items all need a
/// responder-chain selector.
@MainActor
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not supported")
    }

    @objc private func run() {
        handler()
    }
}

/// What the About panel says.
///
/// Filled in rather than left to the bundle: the standard panel shows the
/// name, the icon and the version on its own, and then an empty box where
/// anyone opening it is looking for what the thing is and what they may do
/// with it.
enum AboutPanel {
    static let repository = "https://github.com/sidler/GitHubMonitor"

    static func options() -> [NSApplication.AboutPanelOptionKey: Any] {
        [
            .credits: credits(),
            .applicationName: "GitHub Monitor",
        ]
    }

    /// The panel renders an attributed string, so the text is built rather
    /// than loaded from a Credits file the Makefile would have to copy.
    static func credits() -> NSAttributedString {
        let body = NSMutableAttributedString()

        body.append(line(
            "A menu bar app for the GitHub work waiting on you: the reviews, "
                + "the issues and the mentions, with the diffs and the "
                + "approving close enough that most of it needs no browser.",
            size: 11
        ))
        body.append(line("", size: 5))
        // The licence and the copyright come from the bundle, which the
        // panel prints under this of its own accord -- saying either here
        // as well put the same sentence on screen twice.
        body.append(line("Source at", size: 11))
        body.append(link(repository))

        return body
    }

    private static func line(
        _ text: String, size: CGFloat, colour: NSColor = .labelColor
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            string: text + "\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: colour,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private static func link(_ url: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            string: url + "\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: URL(string: url) as Any,
                .paragraphStyle: paragraph,
            ]
        )
    }
}
