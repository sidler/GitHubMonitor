import Combine
import SwiftUI

/// Which patches the reader has unfolded.
///
/// View-local state without `@State`: its macro implementation ships only
/// with Xcode, and this project builds against the Command Line Tools.
@MainActor
final class PatchExpansion: ObservableObject {
    @Published private var open: Set<String> = []

    func isOpen(_ path: String) -> Bool { open.contains(path) }

    func toggle(_ path: String) {
        if open.contains(path) { open.remove(path) } else { open.insert(path) }
    }
}

/// A unified diff, drawn line by line.
///
/// Horizontally scrollable, like the code blocks in a comment: wrapping a
/// diff line puts the continuation under the next line's marker, which is
/// exactly the confusion a diff exists to avoid.
struct PatchView: View {
    let patch: String
    let language: CodeLanguage?

    private var lines: [Line] {
        patch.components(separatedBy: "\n").enumerated().map { Line(id: $0.offset, text: $0.element) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    row(line.text)
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            Color(nsColor: .quaternaryLabelColor).opacity(0.25),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    private func row(_ text: String) -> some View {
        let kind = Kind(line: text)
        return CodeText(
            source: text,
            // A hunk header is not code, and the marker column at the start
            // of every other line would have the highlighter reading `-` as
            // punctuation before a keyword. Colour the code, not the diff.
            language: kind == .hunk ? nil : language,
            font: .caption2.monospaced()
        )
        .foregroundStyle(kind.textTint)
        .padding(.horizontal, 8)
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
            case .hunk, .context: .clear
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
