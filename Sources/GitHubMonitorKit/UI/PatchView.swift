import Combine
import SwiftUI

/// Which file's diff is open, by position in the list.
///
/// View-local state without `@State`: its macro implementation ships only
/// with Xcode, and this project builds against the Command Line Tools.
@MainActor
final class DiffPresentation: ObservableObject {
    @Published var index: Int?

    var isOpen: Bool { index != nil }

    func open(_ index: Int) { self.index = index }
    func close() { index = nil }

    func step(_ offset: Int, within count: Int) {
        guard let current = index, count > 0 else { return }
        index = min(max(current + offset, 0), count - 1)
    }
}

/// One file's diff, over the whole window.
///
/// A sheet rather than something inside the detail pane: the pane is 280 to
/// 400 points wide, and a diff read three words at a time is not read. The
/// pane lists the files; this is where one is actually looked at.
struct DiffSheet: View {
    let files: [ChangedFile]
    let pullRequest: URL
    @ObservedObject var presentation: DiffPresentation

    private var file: ChangedFile? {
        guard let index = presentation.index, files.indices.contains(index) else { return nil }
        return files[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            body(for: file)
        }
        // Wider than it strictly needs to be: the point of leaving the pane
        // is the room, and a diff is read across, not down.
        .frame(minWidth: 880, idealWidth: 1100, minHeight: 560, idealHeight: 700)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let file {
                Image(systemName: file.change.symbolName)
                    .foregroundStyle(.secondary)
                    .help(file.change.label)
                // The whole path here, where there is room for it: the list
                // in the pane had to cut it down to the last two parts.
                Text(file.path)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)

                if file.additions > 0 {
                    Text(verbatim: "+\(file.additions)")
                        .foregroundStyle(.green).monospacedDigit()
                }
                if file.deletions > 0 {
                    Text(verbatim: "\u{2212}\(file.deletions)")
                        .foregroundStyle(.red).monospacedDigit()
                }
            }

            Spacer(minLength: 12)

            // Only worth the room when there is somewhere to step to.
            if files.count > 1 {
                Text(verbatim: "\((presentation.index ?? 0) + 1) of \(files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button { presentation.step(-1, within: files.count) } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(presentation.index == 0)
                .help("Previous file")

                Button { presentation.step(1, within: files.count) } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(presentation.index == files.count - 1)
                .help("Next file")
            }

            if let file, let url = file.url(pullRequest: pullRequest) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Open this file's diff on GitHub")
            }

            Button("Done") { presentation.close() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private func body(for file: ChangedFile?) -> some View {
        if let patch = file?.patch {
            // The size of the scroll view, handed to what is inside it: a
            // `ScrollView` centres content smaller than its viewport, so a
            // ten-line diff floated in the middle of an empty page. Asking
            // for at least the viewport's size anchors it to the corner,
            // and a longer diff keeps its own size.
            GeometryReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    PatchLines(patch: patch, language: file?.language)
                        .padding(.vertical, 6)
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height,
                            alignment: .topLeading
                        )
                }
            }
        } else {
            ContentUnavailableView(
                "No diff for this file",
                systemImage: "doc.questionmark",
                description: Text(
                    "GitHub sends no patch for a binary file, or for one it judged too large."
                )
            )
        }
    }
}

/// A unified diff, drawn line by line.
///
/// Never wrapped: a wrapped diff line puts its continuation under the next
/// line's marker, which is exactly the confusion a diff exists to avoid. The
/// sheet around it scrolls in both directions instead.
struct PatchLines: View {
    let patch: String
    let language: CodeLanguage?

    private var lines: [Line] {
        patch.components(separatedBy: "\n").enumerated().map { Line(id: $0.offset, text: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                row(line.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ text: String) -> some View {
        let kind = Kind(line: text)
        return CodeText(
            source: text,
            // A hunk header is not code, and the marker column at the start
            // of every other line would have the highlighter reading `-` as
            // punctuation before a keyword. Colour the code, not the diff.
            language: kind == .hunk ? nil : language,
            font: .caption.monospaced()
        )
        .foregroundStyle(kind.textTint)
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.background)
    }

    private struct Line: Identifiable {
        let id: Int
        let text: String
    }

    private enum Kind {
        case added
        case removed
        case hunk
        case context

        init(line: String) {
            if line.hasPrefix("@@") {
                self = .hunk
            } else if line.hasPrefix("+") {
                self = .added
            } else if line.hasPrefix("-") {
                self = .removed
            } else {
                self = .context
            }
        }

        var background: Color {
            switch self {
            case .added: .green.opacity(0.14)
            case .removed: .red.opacity(0.14)
            case .hunk: Color(nsColor: .quaternaryLabelColor).opacity(0.35)
            case .context: .clear
            }
        }

        /// Only the hunk header is recoloured outright; added and removed
        /// lines keep their syntax colours and are told apart by the band
        /// behind them.
        var textTint: Color {
            switch self {
            case .hunk: Color(nsColor: .secondaryLabelColor)
            case .added, .removed, .context: Color(nsColor: .labelColor)
            }
        }
    }
}
