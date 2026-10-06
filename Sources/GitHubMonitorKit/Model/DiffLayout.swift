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
}
