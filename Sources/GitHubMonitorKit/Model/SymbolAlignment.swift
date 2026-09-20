import AppKit

/// Vertical placement of SF Symbols inside an attributed string.
///
/// An `NSTextAttachment` placed on the baseline leaves a symbol visibly higher
/// than the digits beside it, because SF Symbol images carry asymmetric
/// padding around the drawn glyph: the image box is not the glyph box. Working
/// from the image height alone -- the obvious fix -- overshoots in the other
/// direction. So we measure where the ink actually is and centre that.
public enum SymbolAlignment {
    /// Offset from the text baseline at which the image's *bottom edge* must
    /// sit so the glyph's visible ink is centred on the font's cap height.
    ///
    /// - Parameters:
    ///   - imageHeight: full height of the symbol image
    ///   - inkTop: distance from the image's top edge to the first drawn row
    ///   - inkBottom: distance from the image's top edge to the last drawn row
    ///   - capHeight: cap height of the font the symbol sits next to
    public static func baselineOffset(
        imageHeight: CGFloat,
        inkTop: CGFloat,
        inkBottom: CGFloat,
        capHeight: CGFloat
    ) -> CGFloat {
        let inkCentreFromTop = (inkTop + inkBottom) / 2
        let inkCentreFromBottom = imageHeight - inkCentreFromTop
        return capHeight / 2 - inkCentreFromBottom
    }

    /// Vertical extent of the drawn pixels within a symbol image, in points
    /// measured from its top edge. Returns nil for a fully transparent image.
    public static func inkExtent(of image: NSImage) -> (top: CGFloat, bottom: CGFloat)? {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            rep.pixelsHigh > 0, rep.pixelsWide > 0
        else { return nil }

        var firstRow = Int.max
        var lastRow = Int.min
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.05 else { continue }
                firstRow = min(firstRow, y)
                lastRow = max(lastRow, y)
                break
            }
        }
        guard firstRow <= lastRow else { return nil }

        let scale = image.size.height / CGFloat(rep.pixelsHigh)
        return (CGFloat(firstRow) * scale, CGFloat(lastRow + 1) * scale)
    }
}
