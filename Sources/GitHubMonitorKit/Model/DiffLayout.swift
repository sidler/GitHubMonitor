import Foundation

/// Whether a patch is read in one column or two.
public enum DiffLayout: String, CaseIterable, Codable, Sendable {
    /// What a patch is: removals and the additions answering them, one
    /// after another. Narrow, and the only layout that fits beside a
    /// detail pane on a laptop.
    case unified
    /// The old file on the left, the new one on the right. Wider, and far
    /// easier where a line was edited rather than replaced: the word that
    /// changed sits opposite the word it changed from.
    case sideBySide

    public var label: String {
        switch self {
        case .unified: "Unified"
        case .sideBySide: "Side by Side"
        }
    }

    public var symbolName: String {
        switch self {
        case .unified: "list.bullet"
        case .sideBySide: "rectangle.split.2x1"
        }
    }

    /// What rests under the pointer. Two symbols beside each other need
    /// to say what each of them does, not what the pair is about.
    public var tip: String {
        switch self {
        case .unified: "Unified \u{2014} one column, each removal with the addition answering it"
        case .sideBySide: "Side by side \u{2014} two columns, the old file left, the new one right"
        }
    }
}
