import SwiftUI

/// The materials the system draws from macOS 26 on, with the older ones
/// behind them.
///
/// Kept in one place rather than as availability checks scattered through
/// the views: there are only a couple of surfaces in this app that float
/// over content, and they should all be made of the same thing.
extension View {
    /// A panel that floats over whatever is behind the window -- the
    /// popover under the menu bar icon.
    ///
    /// From macOS 26 the system gives such a panel its own material, and an
    /// opaque fill underneath would hide it. Before that the panel was
    /// translucent in a way that dragged the desktop's colour through the
    /// whole thing, which is why there is a fill to hide at all.
    @ViewBuilder
    func panelBackground() -> some View {
        if #available(macOS 26, *) {
            self
        } else {
            background(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// A small thing floating over content: a chart's tooltip.
    ///
    /// Glass where there is glass, and the material plus a hairline where
    /// there is not -- the hairline is what separated the old material from
    /// the content under it, and glass draws its own edge.
    @ViewBuilder
    func floatingBackground(in shape: some InsettableShape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
        }
    }
}

// `scrollEdgeEffectStyle` was tried here and does nothing: the band over the
// title bar is drawn by hand because a SwiftUI `List` on macOS is an
// NSTableView in an NSScrollView, which the modifier does not reach -- the
// same reason `onScrollGeometryChange` never fires for it. Rows scrolled
// straight through the toolbar with the hand-rolled band removed.
