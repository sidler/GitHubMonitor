import Foundation
import Testing

@testable import GitHubMonitorKit

/// Which way a dragged edge moves a panel. The sign is the whole of this
/// and it is exactly the kind of thing that compiles either way.
@MainActor
@Suite("Dragging a panel's edge")
struct PanelDragTests {
    /// The file list beside a diff. Its leading edge is the window's, so
    /// what moves is the trailing one: right is wider.
    @Test("A panel on the left grows as the pointer moves right")
    func leading() {
        #expect(Settings.draggedWidth(from: 260, by: 40, onTrailingEdge: false) == 300)
        #expect(Settings.draggedWidth(from: 260, by: -40, onTrailingEdge: false) == 220)
    }

    /// The strip of facts beside a review. Its trailing edge is the
    /// window's, so what moves is the leading one: left is wider.
    @Test("A panel on the right grows as the pointer moves left")
    func trailing() {
        #expect(Settings.draggedWidth(from: 266, by: -40, onTrailingEdge: true) == 306)
        #expect(Settings.draggedWidth(from: 266, by: 40, onTrailingEdge: true) == 226)
    }

    /// Neither can be dragged past what it is allowed to be.
    @Test("Both are held inside their limits")
    func clamped() {
        #expect(Settings.clampedInspectorWidth(50) == Settings.narrowestDiffInspector)
        #expect(Settings.clampedInspectorWidth(5000) == Settings.widestDiffInspector)
        #expect(Settings.clampedInspectorWidth(300) == 300)
    }
}
