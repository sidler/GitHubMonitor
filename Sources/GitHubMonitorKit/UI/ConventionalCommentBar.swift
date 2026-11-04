import SwiftUI

/// The words a remark can open with, above the box it is written in.
///
/// Above rather than behind a menu because the point of the convention is
/// that you pick one every time: a list you have to open first is a list
/// you stop opening. The second row appears only once a word is chosen --
/// a decoration with nothing to decorate is not a thing the format has.
struct ConventionalCommentBar: View {
    @Binding var text: String
    @ObservedObject var caret: CaretState

    private var head: ConventionalComment.Head? { ConventionalComment.head(of: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowRow(spacing: 3) {
                ForEach(ConventionalComment.labels) { label in
                    chip(label, lit: head?.label == label.name) { pick(label.name) }
                }
            }

            if let head {
                FlowRow(spacing: 3) {
                    ForEach(ConventionalComment.decorations) { mark in
                        chip(mark, lit: head.decoration == mark.name) {
                            decorate(head, with: mark.name)
                        }
                    }
                }
            }
        }
    }

    /// One word. Lit, it is the colour its badge will be; unlit, it is
    /// that colour on a wash of itself, so the row reads as a palette
    /// rather than as twelve buttons.
    private func chip(
        _ label: ConventionalLabel, lit: Bool, press: @escaping () -> Void
    ) -> some View {
        Button(action: press) {
            Text(label.name)
                .font(.system(size: 10, weight: lit ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundStyle(lit ? filled(label) : tint(label))
                .background(
                    lit ? tint(label) : tint(label).opacity(0.14), in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(tint(label).opacity(lit ? 0 : 0.35), lineWidth: 0.5)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(label.summary)
    }

    private func tint(_ label: ConventionalLabel) -> Color {
        guard let parts = label.components else {
            return Color(nsColor: .secondaryLabelColor)
        }
        return Color(red: parts.red, green: parts.green, blue: parts.blue)
    }

    /// What reads on the filled chip. The same reckoning the label chips
    /// in the rest of the app use, because the badge is drawn by the same
    /// rule on GitHub.
    private func filled(_ label: ConventionalLabel) -> Color {
        label.prefersDarkText ? Color(red: 0.1, green: 0.1, blue: 0.1) : .white
    }

    /// Picking the word that is already there takes it off again, which is
    /// the only way back to an unlabelled remark without editing markdown
    /// by hand.
    private func pick(_ name: String) {
        guard head?.label != name else { return write(label: nil, decoration: nil) }
        write(label: name, decoration: head?.decoration)
    }

    private func decorate(_ head: ConventionalComment.Head, with name: String) {
        write(
            label: head.label,
            decoration: head.decoration == name ? nil : name
        )
    }

    private func write(label: String?, decoration: String?) {
        let rewrite = ConventionalComment.applying(
            label: label, decoration: decoration, to: text
        )
        text = rewrite.text
        // The writing carries on where it was. Without this the caret
        // goes wherever the new string happens to leave it, which after a
        // badge is in the middle of a URL.
        caret.wanted = NSRange(location: rewrite.caret(from: caret.offset), length: 0)
    }
}
