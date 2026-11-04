import SwiftUI

/// The formatting buttons above the box a remark is written in.
///
/// Buttons rather than a markdown lesson. GitHub's own box has them, and
/// the things they write are the things that are tedious to type and easy
/// to get wrong by hand: the backticks round a path, the asterisks round
/// a word, the mark in front of every line of a list.
///
/// Not a rich text field, and deliberately. What is sent to GitHub is
/// markdown, and a field that hid the markdown would be a field that
/// quietly disagreed with what arrives there. The box shows what will be
/// sent; *Preview* shows what it will look like.
struct MarkdownBar: View {
    @Binding var text: String
    @ObservedObject var caret: CaretState
    @Binding var previewing: Bool

    /// In groups, with a hairline between them: four about a word, one
    /// about a link, four about whole lines.
    private static let groups: [[MarkdownAction]] = [
        [.bold, .italic, .strikethrough, .code],
        [.link],
        [.quote, .bullet, .number, .task],
    ]

    var body: some View {
        HStack(spacing: 3) {
            // Nothing to format while the markdown is not on screen.
            if !previewing {
                ForEach(Array(Self.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        Divider().frame(height: 11)
                    }
                    ForEach(group) { action in
                        button(action)
                    }
                }
            }

            Spacer(minLength: 6)

            Toggle(isOn: $previewing) {
                Label("Preview", systemImage: "eye")
                    .font(.system(size: 10))
            }
            .toggleStyle(.button)
            .buttonStyle(.accessoryBar)
            .controlSize(.small)
            .pointerStyle(.link)
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .help(
                previewing
                    ? "Back to writing \u{2014} \u{21E7}\u{2318}P"
                    : "Read the remark as it will be sent \u{2014} \u{21E7}\u{2318}P"
            )
        }
    }

    private func button(_ action: MarkdownAction) -> some View {
        Button {
            apply(action)
        } label: {
            Image(systemName: Self.symbol(action))
                .font(.system(size: 11))
                .frame(width: 15)
        }
        .buttonStyle(.accessoryBar)
        .controlSize(.small)
        .pointerStyle(.link)
        .help(Self.title(action))
        .modifier(Shortcut(key: Self.shortcut(action)))
    }

    private func apply(_ action: MarkdownAction) {
        let written = MarkdownEditing.applying(
            action, to: text, selection: caret.selection
        )
        text = written.text
        caret.wanted = written.selection
    }

    /// Only the four everybody already knows from every other editor.
    /// A shortcut per button would mean inventing eight, and an invented
    /// shortcut is one that collides with something on somebody's
    /// keyboard layout.
    private static func shortcut(_ action: MarkdownAction) -> KeyEquivalent? {
        switch action {
        case .bold: return "b"
        case .italic: return "i"
        case .code: return "e"
        case .link: return "k"
        default: return nil
        }
    }

    private static func symbol(_ action: MarkdownAction) -> String {
        switch action {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .quote: return "text.quote"
        case .bullet: return "list.bullet"
        case .number: return "list.number"
        case .task: return "checklist"
        }
    }

    private static func title(_ action: MarkdownAction) -> String {
        switch action {
        case .bold: return "Bold \u{2014} \u{2318}B"
        case .italic: return "Italic \u{2014} \u{2318}I"
        case .strikethrough: return "Strikethrough"
        case .code: return "Code \u{2014} \u{2318}E"
        case .link: return "Link \u{2014} \u{2318}K"
        case .quote: return "Quote"
        case .bullet: return "Bulleted list"
        case .number: return "Numbered list"
        case .task: return "Task list"
        }
    }

    /// `keyboardShortcut` takes no optional, and a view with one is a
    /// different type from a view without.
    private struct Shortcut: ViewModifier {
        let key: KeyEquivalent?

        func body(content: Content) -> some View {
            if let key {
                content.keyboardShortcut(key, modifiers: .command)
            } else {
                content
            }
        }
    }
}
