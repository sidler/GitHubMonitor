import AppKit
import SwiftUI

/// A pick between a handful of symbols, drawn the way macOS draws one.
///
/// An `NSSegmentedControl` of its own rather than a SwiftUI `Picker`,
/// and for one reason: the tooltips. A `.help` written on the items of a
/// segmented picker is dropped -- measured rather than assumed, by
/// building one and asking the control it makes: both segments come back
/// with no tooltip at all. So the only tooltip such a picker can carry is
/// one for the whole control, which says what the pair of them is about
/// and nothing about which is which. That is no use when the two are
/// symbols a few points apart and the question is what each one does.
///
/// Here every segment carries its own, which is the whole point of
/// drawing this by hand.
struct SymbolChoice<Tag: Hashable>: NSViewRepresentable {
    struct Option {
        let tag: Tag
        /// The SF Symbol on the segment.
        let symbolName: String
        /// What it is called, which is also what a screen reader says.
        let label: String
        /// What it does, which is what rests under the pointer.
        let tip: String

        init(tag: Tag, symbolName: String, label: String, tip: String) {
            self.tag = tag
            self.symbolName = symbolName
            self.label = label
            self.tip = tip
        }
    }

    let options: [Option]
    let selection: Tag
    let choose: (Tag) -> Void

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        control.segmentCount = options.count
        control.target = context.coordinator
        control.action = #selector(Coordinator.pressed(_:))
        apply(to: control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        apply(to: control)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }

    private func apply(to control: NSSegmentedControl) {
        for (index, option) in options.enumerated() {
            // The description is what VoiceOver reads off the segment:
            // an image with none is a button with no name.
            control.setImage(
                NSImage(
                    systemSymbolName: option.symbolName,
                    accessibilityDescription: option.label
                ),
                forSegment: index
            )
            control.setToolTip(option.tip, forSegment: index)
        }
        if let index = options.firstIndex(where: { $0.tag == selection }) {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: SymbolChoice

        init(_ parent: SymbolChoice) {
            self.parent = parent
        }

        @objc func pressed(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard parent.options.indices.contains(index) else { return }
            parent.choose(parent.options[index].tag)
        }
    }
}
