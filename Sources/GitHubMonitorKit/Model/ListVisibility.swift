import Foundation

/// The three things the app watches, as the user thinks of them.
///
/// "My Pull Requests" is not among them: it exists only in the window, has
/// no count of its own anywhere, and a switch for it would sit in two
/// columns that could never do anything.
public enum WatchedList: String, CaseIterable, Codable, Sendable, Identifiable {
    case reviews
    case issues
    case mentions

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .reviews: "Reviews requested"
        case .issues: "Issues assigned"
        case .mentions: "Mentions"
        }
    }

    public var symbolName: String {
        switch self {
        case .reviews: StatusBarTitleBuilder.pullRequestSymbol
        case .issues: StatusBarTitleBuilder.issueSymbol
        case .mentions: StatusBarTitleBuilder.mentionSymbol
        }
    }

    /// What the menu bar's tooltip and the accessibility label call it.
    public var countPhrase: String {
        switch self {
        case .reviews: "reviews requested"
        case .issues: "issues assigned"
        case .mentions: "unread mentions"
        }
    }
}

/// Where a list can appear.
public enum DisplaySurface: String, CaseIterable, Codable, Sendable, Identifiable {
    case menuBar
    case popover
    case window

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .menuBar: "Menu bar"
        case .popover: "Popover"
        case .window: "Window"
        }
    }

    public var help: String {
        switch self {
        case .menuBar: "The count beside the icon in the menu bar"
        case .popover: "The section in the panel under the menu bar icon"
        case .window: "The section in the window's sidebar, and its count in the status bar"
        }
    }
}

/// Which lists are shown where.
///
/// Stored as what is *hidden* rather than what is shown: everything counts
/// until it is switched off, so a list added later appears by itself instead
/// of staying invisible until someone finds the switch.
public struct ListVisibility: Equatable, Sendable {
    private var hidden: Set<String>

    public init(hidden: Set<String> = []) {
        self.hidden = hidden
    }

    public init(storedKeys: [String]) {
        hidden = Set(storedKeys)
    }

    static func key(_ list: WatchedList, _ surface: DisplaySurface) -> String {
        "\(list.rawValue).\(surface.rawValue)"
    }

    public func isShown(_ list: WatchedList, in surface: DisplaySurface) -> Bool {
        !hidden.contains(Self.key(list, surface))
    }

    /// Whether anything still shows this list, so the app can tell "switched
    /// off here" from "switched off everywhere".
    public func isShownAnywhere(_ list: WatchedList) -> Bool {
        DisplaySurface.allCases.contains { isShown(list, in: $0) }
    }

    public mutating func setShown(_ shown: Bool, _ list: WatchedList, in surface: DisplaySurface) {
        if shown {
            hidden.remove(Self.key(list, surface))
        } else {
            hidden.insert(Self.key(list, surface))
        }
    }

    /// The lists one surface shows, in the order they are listed everywhere.
    public func shown(in surface: DisplaySurface) -> [WatchedList] {
        WatchedList.allCases.filter { isShown($0, in: surface) }
    }

    /// Sorted, so the stored value does not churn with set ordering.
    public var storedKeys: [String] { hidden.sorted() }
}
