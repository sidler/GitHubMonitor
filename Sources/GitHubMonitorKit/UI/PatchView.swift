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
    /// The pull request being read, where one is known. Nil leaves the
    /// overlay a reader and nothing more.
    var review: ReviewActions?
    /// The pull request itself and what it answers, for the panel in the
    /// header. Nil where the overlay was opened without one.
    var subject: LinkedSubject?
    /// Which files have been ticked off, and how to tick one. Nil leaves
    /// the overlay a reader with no checkboxes.
    var viewed: ViewedFiles?

    @StateObject private var open = OpenFolders()

    var body: some View {
        ZStack {
            // The dimmed ground is part of the control: clicking beside a
            // window that covers what you were reading should put it away,
            // and reaching for the button is the long way round.
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            card
                // The shadow belongs to the shape behind the card, not to
                // the card: `.shadow` on the content shadows everything
                // drawn in it, so the divider between the file list and the
                // diff was casting one across the first inch of every patch.
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1)
                )
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
            // The number a review is actually measured against, next to the
            // one it is measured out of.
            if let viewed, viewed.count(of: files) > 0 {
                Text("\(viewed.count(of: files)) of \(files.count) viewed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if additions > 0 {
                Text(verbatim: "+\(additions)").foregroundStyle(.green).monospacedDigit()
            }
            if deletions > 0 {
                Text(verbatim: "\u{2212}\(deletions)").foregroundStyle(.red).monospacedDigit()
            }

            if let subject {
                Divider().frame(height: 14)
                // Beside the counts rather than beside Done: it belongs to
                // what is being read, not to the controls for leaving.
                LinkedSubjectButton(subject: subject)
            }

            Spacer(minLength: 12)

            if let review {
                reviewControls(review)
                Divider().frame(height: 14)
            }

            Button { NSWorkspace.shared.open(pullRequest.appendingPathComponent("files")) } label: {
                Label("All files on GitHub", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.accessoryBar)

            Button("Done", action: close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
        .alert(
            "Approve \u{201c}\(review?.title ?? "")\u{201d}?",
            isPresented: Binding(
                get: { review?.isConfirming ?? false },
                set: { if !$0 { review?.cancel() } }
            )
        ) {
            Button("Approve") { Task { await submit() } }
            Button("Cancel", role: .cancel) { review?.cancel() }
        } message: {
            Text(confirmation)
        }
    }

    // MARK: - Reviewing

    /// What the header offers, which depends on where this person already
    /// stands on the pull request.
    @ViewBuilder
    private func reviewControls(_ review: ReviewActions) -> some View {
        if let message = review.failure {
            // Nothing was written; say why, and leave the button usable.
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: 320, alignment: .trailing)
        }

        if review.didAuthor {
            // GitHub refuses it, so the button would be a button that never
            // works. Saying why is more use than a disabled control.
            Text("Your own pull request")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if review.viewerState == .approved {
            Label("Approved", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            if review.viewerState == .changesRequested {
                // The button still works, and this says what it will undo.
                Text("You asked for changes")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Request changes\u{2026}") {
                NSWorkspace.shared.open(pullRequest.appendingPathComponent("files"))
            }
            .help("Opens the pull request on GitHub, where a review can be written against the lines")

            Button("Approve") { Task { await review.ask() } }
                .disabled(review.isBusy)
        }
    }

    private var confirmation: String {
        guard let review else { return "" }
        return ApprovalQuery.confirmation(
            repository: review.repository,
            number: review.number,
            isAutoMergeArmed: review.isAutoMergeArmed
        )
    }

    private func submit() async {
        guard let review else { return }
        if await review.approve() { close() }
    }

    private var additions: Int { files.reduce(0) { $0 + $1.additions } }
    private var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

    /// The list on the left, as the directories the files live in.
    ///
    /// Bound to the same value the scroll position writes, so clicking jumps
    /// and scrolling moves the highlight.
    private var index: some View {
        List(selection: $path) {
            FileTreeRows(nodes: FileTree.build(files), open: open, viewed: viewed?.states ?? [:])
        }
        // Inset rather than sidebar: the sidebar style draws an edge shadow
        // down its trailing side, which fell across the diff beside it.
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
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
        let state = viewed?.state(file.path) ?? .unviewed
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let viewed {
                    Button { viewed.toggle(file.path) } label: {
                        Image(systemName: state.symbolName)
                            .foregroundStyle(tint(for: state))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(state.label)
                }

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

            // A ticked file keeps its header and its place, and folds the
            // patch away. Folded rather than hidden: the point of the tick
            // is "done with this for now", not "never show me again".
            if state.isFolded {
                Text("Viewed \u{2014} click the tick to unfold it again")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else if let patch = file.patch {
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

extension DiffOverlay {
    fileprivate func tint(for state: FileViewedState) -> Color {
        switch state {
        case .unviewed: Color(nsColor: .secondaryLabelColor)
        case .viewed: .green
        // The one that needs reading again, and the only one drawn in a
        // colour that asks for attention.
        case .dismissed: .orange
        }
    }
}

/// What the overlay may do with the ticks beside its files.
///
/// The state itself rather than a copy of it, which is the difference
/// between a tick that appears when it is pressed and one that appears
/// after the next launch: a snapshot taken when the overlay was built does
/// not change when the tick does, and the view has nothing to redraw for.
/// Read during `body`, so the view follows the state the way any other
/// observed read does.
@MainActor
struct ViewedFiles {
    let app: AppState
    let pullRequestID: String
    let toggle: (String) -> Void

    var states: [String: FileViewedState] { app.viewedFiles[pullRequestID] ?? [:] }

    func state(_ path: String) -> FileViewedState {
        app.viewedState(of: path, in: pullRequestID)
    }

    /// How many of these files are ticked off, for the header.
    func count(of files: [ChangedFile]) -> Int {
        app.viewedCount(of: files, in: pullRequestID)
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
        // In a plain rectangle: a bare colour background rounds its
        // corners on this system, which made every added and removed line
        // look like a pill.
        .background(kind.background, in: Rectangle())
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

/// Which folders in the diff's file tree are open.
///
/// Everything is open to begin with: a diff is read rather than explored,
/// and a tree that arrives shut is a tree to click open before it says
/// anything. A folder closed by hand stays closed while the overlay is up.
@MainActor
final class OpenFolders: ObservableObject {
    @Published private var closed: Set<String> = []

    func binding(for path: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in !(self?.closed.contains(path) ?? false) },
            set: { [weak self] isOpen in
                if isOpen { self?.closed.remove(path) } else { self?.closed.insert(path) }
            }
        )
    }
}

/// One level of the file tree, and the levels under it.
///
/// `AnyView` around the recursion: a `some View` body that mentions its own
/// type is a type that contains itself, which the compiler will not build.
struct FileTreeRows: View {
    let nodes: [FileTree.Node]
    @ObservedObject var open: OpenFolders
    /// Where each file stands, so the list used for jumping also says what
    /// is left to read. Empty where the overlay has no ticks.
    var viewed: [String: FileViewedState] = [:]

    var body: some View {
        ForEach(nodes) { node in
            switch node {
            case .file(let file):
                fileRow(file).tag(file.path)
            case .folder(let folder):
                DisclosureGroup(isExpanded: open.binding(for: folder.path)) {
                    AnyView(FileTreeRows(nodes: folder.children, open: open, viewed: viewed))
                } label: {
                    folderRow(folder)
                }
            }
        }
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        let state = viewed[file.path] ?? .unviewed
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: file.change.symbolName)
                .foregroundStyle(.secondary)
            // The name only: the folders above it carry the rest, which is
            // the whole point of the tree.
            Text((file.path as NSString).lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(state == .viewed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if state != .unviewed {
                Image(systemName: state.symbolName)
                    .font(.caption)
                    .foregroundStyle(state == .viewed ? Color.green : Color.orange)
                    .help(state.label)
            }
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
    }

    private func folderRow(_ folder: FileTree.Folder) -> some View {
        HStack(spacing: 6) {
            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            Text(verbatim: "\(folder.files.count)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .help(folder.path)
    }
}

/// What the diff overlay may do with the pull request it is showing.
///
/// A plain description rather than the app's state, so the overlay stays a
/// view: it asks whether it may offer the button, and hands the two verbs
/// back to whoever built it.
struct ReviewActions {
    let title: String
    let repository: String
    let number: Int
    let didAuthor: Bool
    let viewerState: ReviewState?
    let isAutoMergeArmed: Bool
    let isBusy: Bool
    /// Whether the question is on screen for this pull request.
    let isConfirming: Bool
    /// Why the last attempt wrote nothing, if there was one.
    let failure: String?
    /// Looks at the head commit and, if it still matches, raises the
    /// question. Writes nothing either way.
    let ask: () async -> Void
    let cancel: () -> Void
    /// True when GitHub took the approval.
    let approve: () async -> Bool
}
