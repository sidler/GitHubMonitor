import AppKit
import Testing
@testable import GitHubMonitorKit

@Suite("Symbol alignment")
struct SymbolAlignmentTests {
    /// Ink filling the whole image and exactly as tall as the cap height needs
    /// no correction at all.
    @Test("Ink matching the cap height sits on the baseline")
    func inkMatchingCapHeight() {
        let offset = SymbolAlignment.baselineOffset(
            imageHeight: 10, inkTop: 0, inkBottom: 10, capHeight: 10
        )
        #expect(offset == 0)
    }

    /// The real case: a symbol taller than the cap height has to drop below
    /// the baseline for its middle to line up with the digits.
    @Test("Ink taller than the cap height drops below the baseline")
    func tallInkDropsBelowBaseline() {
        let offset = SymbolAlignment.baselineOffset(
            imageHeight: 17, inkTop: 2, inkBottom: 15, capHeight: 10
        )
        #expect(offset < 0)
        // Ink centre is 8.5 from the top, so 8.5 from the bottom; it must end
        // up 5 above the baseline.
        #expect(offset == 5 - 8.5)
    }

    /// Padding above the glyph must not be mistaken for glyph height -- that
    /// was the original bug.
    @Test("Asymmetric padding is accounted for")
    func asymmetricPadding() {
        let balanced = SymbolAlignment.baselineOffset(
            imageHeight: 20, inkTop: 5, inkBottom: 15, capHeight: 10
        )
        let topHeavy = SymbolAlignment.baselineOffset(
            imageHeight: 20, inkTop: 0, inkBottom: 10, capHeight: 10
        )
        // Ink sitting higher in the image must be pushed further down.
        #expect(topHeavy < balanced)
    }

    @Test("Ink extent of a real SF Symbol is inside the image and non-empty")
    func inkExtentOfRealSymbol() throws {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = try #require(
            NSImage(systemSymbolName: StatusBarTitleBuilder.mentionSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        )
        let extent = try #require(SymbolAlignment.inkExtent(of: image))
        #expect(extent.top >= 0)
        #expect(extent.bottom <= image.size.height)
        #expect(extent.bottom > extent.top)
        // SF Symbols pad their images; ink never fills the box edge to edge.
        #expect(extent.bottom - extent.top < image.size.height)
    }

    @Test("A transparent image reports no ink")
    func transparentImage() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        #expect(SymbolAlignment.inkExtent(of: image) == nil)
    }
}
