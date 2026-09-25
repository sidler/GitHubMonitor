import Combine
import SwiftUI

/// Every file a pull request touches, one after another, over the window.
///
/// Over the window rather than inside the detail pane: the pane is 280 to
/// 400 points wide, and a diff read three words at a time is not read. The
/// pane lists the files; this is where they are actually looked at.
///
/// Scrolled rather than paged. A review is read from top to bottom, and the
/// list on the left is a way to jump, not the only way to move: it follows
/// the scrolling as well as driving it.
struct DiffOverlay: View {
    let files: [ChangedFile]
    let pullRequest: URL
    @Binding var path: String?
    let close: () -> Void

    var body: some View {
        ZStack {
            // The dimmed ground is part of the control: clicking beside a
            // window that covers what you were reading should put it away,
            // and reaching for the button is the long way round.
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            card
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                // Capped, so a large window leaves a border of ground worth
                // aiming at rather than a hairline. A small one still gets
                // everything it has.
                .frame(maxWidth: 1500, maxHeight: 1100)
                .padding(36)
        }
        // Escape is handled by the view that hosts this, so that it stops
        // here instead of reaching the list behind it.
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                index
                Divider()
                diffs
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(files.count) file\(files.count == 1 ? "" : "s") changed")
                .font(.headline)
            if additions > 0 {
                Text(verbatim: "+\(additions)").foregroundStyle(.green).monospacedDigit()
            }
            if deletions > 0 {
                Text(verbatim: "\u{2212}\(deletions)").foregroundStyle(.red).monospacedDigit()
            }

            Spacer(minLength: 12)

            Button { NSWorkspace.shared.open(pullRequest.appendingPathComponent("files")) } label: {
                Label("All files on GitHub", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.accessoryBar)

            Button("Done", action: close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private var additions: Int { files.reduce(0) { $0 + $1.additions } }
    private var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

    /// The list on the left. Bound to the same value the scroll position
    /// writes, so clicking jumps and scrolling moves the highlight.
    private var index: some View {
        List(selection: $path) {
            ForEach(files) { file in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: file.change.symbolName)
                        .foregroundStyle(.secondary)
                    Text(file.shortPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 4)
                    if file.additions > 0 {
                        Text(verbatim: "+\(file.additions)")
                            .foregroundStyle(.green).monospacedDigit()
                    }
                    if file.deletions > 0 {
                        Text(verbatim: "\u{2212}\(file.deletions)")
                            .foregroundStyle(.red).monospacedDigit()
                    }
                }
                .font(.caption)
                .help(file.path)
                .tag(file.path)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 260)
    }

    private var diffs: some View {
        // The width is measured and handed down: inside a horizontal scroll
        // view `maxWidth: .infinity` resolves to the content's own width, so
        // every band stopped at the end of its longest line and a diff of
        // short lines sat in a narrow column of colour.
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(files) { file in
                        fileSection(file, width: proxy.size.width)
                            .id(file.path)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollPosition(id: $path, anchor: .top)
        }
    }

    private func fileSection(_ file: ChangedFile, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: file.change.symbolName)
                    .foregroundStyle(.secondary)
                    .help(file.change.label)
                // The whole path here, where there is room for it: the list
                // beside it has to cut it down to the last two parts.
                Text(file.path)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)

                if let url = file.url(pullRequest: pullRequest) {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.accessoryBar)
                    .help("Open this file's diff on GitHub")
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)

            if let patch = file.patch {
                // Its own horizontal scroll, so a long line moves without
                // dragging the file above it sideways too.
                ScrollView(.horizontal, showsIndicators: false) {
                    PatchLines(patch: patch, language: file.language)
                        .padding(.vertical, 6)
                        // At least the width of the column, so the added and
                        // removed bands run the whole way across; a longer
                        // line still makes it wider and scrolls.
                        .frame(minWidth: width, alignment: .leading)
                }
            } else {
                Text("GitHub sends no diff for this file \u{2014} it is binary, or too large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
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
