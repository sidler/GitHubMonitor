import SwiftUI

/// What a filter box means by a match.
///
/// One rule rather than three: the list of pull requests, the list of
/// issues and the diff's file tree all have a box over them, and a box
/// that matched differently depending on what it sat over would be three
/// boxes that look alike.
enum TextFilter {
    /// What was actually typed, or nil where nothing was. Spaces alone
    /// are nothing: a stray space should not empty a list.
    static func query(_ typed: String) -> String? {
        let wanted = typed.trimmingCharacters(in: .whitespaces)
        return wanted.isEmpty ? nil : wanted
    }

    /// Anywhere in the text, in any case. A filter box is for finding the
    /// row you half remember, not for writing a pattern.
    static func keeps(_ text: String, matching typed: String) -> Bool {
        guard let wanted = query(typed) else { return true }
        return text.localizedCaseInsensitiveContains(wanted)
    }
}

/// A free-text box over a list.
///
/// Hand-built rather than `.searchable`: that one puts its field in the
/// window's toolbar, and the diff's file tree is in a window whose
/// toolbar belongs to the review -- so two of the three boxes could not
/// have been one.
struct FilterField: View {
    let prompt: String
    @Binding var text: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)

            // Only once there is something to clear: an X on an empty box
            // offers to undo nothing.
            if TextFilter.query(text) != nil {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear the filter")
                .accessibilityLabel("Clear the filter")
            }
        }
        .font(.callout)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
        // Command-F puts the cursor in here. A button behind the box
        // rather than a Find item in the menu: every window that has one
        // of these has its own, and the shortcut should reach the one in
        // front of you rather than whichever view answered first.
        //
        // Behind rather than hidden: a view with `hidden()` is out of the
        // layout, and a shortcut on one out of the layout never fires.
        .background {
            Button("Filter") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}
