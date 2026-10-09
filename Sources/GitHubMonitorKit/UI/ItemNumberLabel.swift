import AppKit
import SwiftUI

/// Where an item lives and what it is called there, with the number worth
/// clicking.
///
/// The number is what somebody came to the pane for: it goes into a commit
/// message, a chat, a branch name. It used to be the tail of one string
/// that also carried the repository, in a row beside the author and the
/// date -- and in a pane this narrow that string is truncated from the
/// end, so the number was the first thing to go. Here the repository gives
/// way instead, in the middle, and the number never does.
struct ItemNumberLabel: View {
    let repository: String
    let number: Int

    @StateObject private var copied = CopyFlash()

    /// What the clipboard gets. The bare form, which is what reads well in
    /// a commit message and what GitHub links by itself within the
    /// repository the item is already in.
    private var text: String { "#\(number)" }

    var body: some View {
        HStack(spacing: 4) {
            Text(repository)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied.flash()
            } label: {
                HStack(spacing: 3) {
                    Text(verbatim: text)
                    Image(systemName: copied.isOn ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(
                            copied.isOn ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary)
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(copied.isOn ? "Copied \(text)" : "Copy \(text)")
            // The repository name may give way. The number may not.
            .layoutPriority(1)
            .fixedSize()
        }
    }
}

/// Says that something was copied, briefly.
///
/// A clipboard write leaves nothing on screen, so a click on the number
/// would otherwise look like a click that did nothing at all.
///
/// An object rather than `@State`: this package builds without Xcode,
/// where the `State` macro is not available.
@MainActor
private final class CopyFlash: ObservableObject {
    @Published private(set) var isOn = false
    private var clearing: Task<Void, Never>?

    func flash() {
        isOn = true
        clearing?.cancel()
        clearing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.isOn = false
        }
    }
}
