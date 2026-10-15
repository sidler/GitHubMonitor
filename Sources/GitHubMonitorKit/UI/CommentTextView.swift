import AppKit
import SwiftUI

/// Where the insertion point is, and where it should go next.
///
/// The box and the list of names have to agree about two things that
/// SwiftUI's own editor keeps to itself: where the caret sits on screen,
/// so the list can be put under it, and where in the text it is, so the
/// half-typed name in front of it can be read.
@MainActor
final class CaretState: ObservableObject {
    /// The caret's rectangle in the box's own coordinates.
    @Published var rect: CGRect = .zero
    /// Where the caret is, counted the way an `NSTextView` counts.
    @Published var offset: Int = 0
    /// Where to put it on the next pass, once. Set when something is
    /// written into the text from outside -- after a name is inserted the
    /// caret belongs behind it, not where the old string happened to end.
    var wanted: Int?
}

/// The box a remark is written in.
///
/// An `NSTextView` rather than a `TextEditor`, for two things the latter
/// does not offer on this toolchain: the caret's position, and a say in
/// what the arrow keys do. Without the first the list of names has to go
/// under the box, where it changes the box's height and makes the diff
/// jump about as names are typed; without the second the list cannot be
/// driven from the keyboard at all, because the box keeps every key for
/// the prose.
struct CommentTextView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var caret: CaretState
    var fontSize: Double = NSFont.systemFontSize
    /// Whether a list of names is on screen. The arrow keys mean
    /// something else while it is.
    var isCompleting: () -> Bool = { false }
    /// Up or down through that list.
    var onMove: (Int) -> Void = { _ in }
    /// Take the highlighted name. Answers whether it took one -- a return
    /// that completes nothing is a new paragraph, as it always was.
    var onCommit: () -> Bool = { false }
    var onCancel: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        // A remark is prose about code: the substitutions that help a
        // sentence hurt a path, a flag and a snippet of a diff.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.textContainerInset = NSSize(width: 3, height: 4)
        view.font = NSFont.systemFont(ofSize: fontSize)
        view.string = text
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.scroll = scroll
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if view.string != text {
            view.string = text
        }
        if let wanted = caret.wanted {
            caret.wanted = nil
            let bounded = max(0, min(wanted, view.string.utf16.count))
            view.setSelectedRange(NSRange(location: bounded, length: 0))
        }
        if view.font?.pointSize != CGFloat(fontSize) {
            view.font = NSFont.systemFont(ofSize: fontSize)
        }
        // Not during the update itself: writing to an observed object
        // while the view that observes it is being built is the one thing
        // SwiftUI asks you not to do.
        context.coordinator.reportLater(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommentTextView
        weak var scroll: NSScrollView?

        init(_ parent: CommentTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            report(view)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            report(view)
        }

        /// The keys the list wants, and only while it is there.
        ///
        /// Everything else falls through to the text view, which is what
        /// makes this safe: with no list on screen the box behaves
        /// exactly as it did, return included.
        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard parent.isCompleting() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertTab(_:)):
                return parent.onCommit()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        func reportLater(_ view: NSTextView) {
            DispatchQueue.main.async { [weak self] in
                guard let self, view.window != nil else { return }
                report(view)
            }
        }

        private func report(_ view: NSTextView) {
            let offset = view.selectedRange().location
            let rect = caretRect(in: view)
            if parent.caret.offset != offset { parent.caret.offset = offset }
            if parent.caret.rect != rect { parent.caret.rect = rect }
        }

        /// The caret's rectangle, in the coordinates of the box as SwiftUI
        /// sees it -- which is the scroll view, so what has been scrolled
        /// out of sight comes off the top.
        private func caretRect(in view: NSTextView) -> CGRect {
            guard
                let layout = view.layoutManager,
                let container = view.textContainer
            else { return .zero }

            let caret = NSRange(location: view.selectedRange().location, length: 0)
            let glyphs = layout.glyphRange(forCharacterRange: caret, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += view.textContainerOrigin.x
            rect.origin.y += view.textContainerOrigin.y
            // An empty range has no width, and a line nobody has typed on
            // yet has no height worth the name.
            if rect.width < 1 { rect.size.width = 1 }
            if rect.height < 1 { rect.size.height = ceil(view.font?.pointSize ?? 13) + 4 }
            if let clip = scroll?.contentView {
                rect.origin.y -= clip.bounds.origin.y
                rect.origin.x -= clip.bounds.origin.x
            }
            return rect
        }
    }
}
