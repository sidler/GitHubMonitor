import Foundation

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

/// One line of the menu bar, the popover or the window's status bar.
public struct SurfaceCount: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let symbolName: String
    public let count: Int

    public init(id: String, title: String, symbolName: String, count: Int) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.count = count
    }
}

/// Which lists are shown where.
///
/// Keyed by the list's own id, plus one fixed key for the mentions, which
/// are not a saved list: they come from the notifications API rather than
/// from a search, and there is exactly one of them.
///
/// Stored as what is *hidden* rather than what is shown: a list counts
/// everywhere until it is switched off, so a list made later appears by
/// itself instead of staying invisible until someone finds the switch.
public struct ListVisibility: Equatable, Sendable {
    /// The mentions' key. Not a UUID, so it survives every migration.
    public static let mentionsKey = "mentions"

    private var hidden: Set<String>

    public init(hidden: Set<String> = []) {
        self.hidden = hidden
    }

    public init(storedKeys: [String]) {
        hidden = Set(storedKeys)
    }

    static func key(_ list: String, _ surface: DisplaySurface) -> String {
        "\(list).\(surface.rawValue)"
    }

    public func isShown(_ list: String, in surface: DisplaySurface) -> Bool {
        !hidden.contains(Self.key(list, surface))
    }

    /// Whether anything still shows this list, which is what decides whether
    /// it is worth a request at all.
    public func isShownAnywhere(_ list: String) -> Bool {
        DisplaySurface.allCases.contains { isShown(list, in: $0) }
    }

    public mutating func setShown(_ shown: Bool, _ list: String, in surface: DisplaySurface) {
        if shown {
            hidden.remove(Self.key(list, surface))
        } else {
            hidden.insert(Self.key(list, surface))
        }
    }

    /// Forgets a deleted list, so its switches do not outlive it in the
    /// stored settings.
    public mutating func forget(_ list: String) {
        for surface in DisplaySurface.allCases {
            hidden.remove(Self.key(list, surface))
        }
    }

    /// Sorted, so the stored value does not churn with set ordering.
    public var storedKeys: [String] { hidden.sorted() }
}
