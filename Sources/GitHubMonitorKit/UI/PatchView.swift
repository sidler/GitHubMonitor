import AppKit
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
    /// The file to put at the top when the overlay opens. After that the
    /// overlay keeps its own place.
    let startingPath: String?
    /// How wide the file list starts, and where to write it once it has
    /// been moved. Nil leaves the divider fixed.
    var startingSidebarWidth: Double = Settings.defaultDiffSidebarWidth
    var setSidebarWidth: ((Double) -> Void)?
    let close: () -> Void
    /// The pull request being read, where one is known. Nil leaves the
    /// overlay a reader and nothing more.
    var review: ReviewActions?
    /// The pull request itself and what it answers, for the panel in the
    /// header. Nil where the overlay was opened without one.
    var subject: LinkedSubject?
    /// How large the patch text is. Read from the settings by whoever
    /// builds the overlay, so a change reaches an open diff.
    var fontSize: Double = Settings.defaultDiffFontSize
    /// Whether each line carries its number in both files.
    var showsLineNumbers: Bool = true
    /// One column or two.
    var layout: DiffLayout = .unified
    /// The conversations from the review, to draw under the lines they
    /// hang on. Empty where none arrived, or none were asked for.
    var threads: [ReviewThread] = []
    /// How to change it from the header. Nil leaves the control off, for
    /// an overlay built without anywhere to write the choice.
    var setLayout: ((DiffLayout) -> Void)?
    /// Which files have been ticked off, and how to tick one. Nil leaves
    /// the overlay a reader with no checkboxes.
    var viewed: ViewedFiles?

    @StateObject private var open = OpenFolders()
    @StateObject private var sidebar = SidebarWidth()
    /// Which file is at the top of the column, kept here rather than in the
    /// app's state.
    ///
    /// Scrolling writes this on every frame. Through the app's state it
    /// went out to the window controller, which rebuilt the whole overlay
    /// and handed the scroll view its position again -- which SwiftUI took
    /// for an instruction and used to pull the file being read back to the
    /// top. The diff could be scrolled from file to file and barely at all
    /// within one, which with short files looked almost like scrolling.
    @StateObject private var place = DiffPlace()

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
                // As wide as the window, less a border of ground worth
                // aiming at: clicking beside the card puts it away, and a
                // hairline is not something anybody can hit. Width is not
                // capped beyond that -- a diff read on a wide screen is
                // exactly where two columns of code have somewhere to go.
                .frame(maxHeight: 1100)
                .padding(36)
        }
        .onAppear {
            // Once, so that opening on a file lands on it and scrolling
            // afterwards is nobody's business but the overlay's.
            if place.path == nil { place.path = startingPath }
            sidebar.width = Settings.clampedSidebarWidth(startingSidebarWidth)
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
                handle
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

            if let setLayout {
                // Here as well as in Settings and the View menu, because
                // which layout suits a patch is decided by looking at the
                // patch: a file of replaced lines reads better in two
                // columns, a file of insertions in one.
                Picker("", selection: Binding(get: { layout }, set: setLayout)) {
                    ForEach(DiffLayout.allCases, id: \.self) { option in
                        Image(systemName: option.symbolName)
                            .help(option.label)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("How the patch is laid out")
                Divider().frame(height: 14)
            }

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
        // No `selection:`. A list whose rows are a flat `ForEach` of
        // mixed kinds would neither mark the chosen file nor let one be
        // chosen -- which is also why clicking a file in the tree never
        // moved the diff. The mark and the click are drawn and handled
        // here instead, where they can be seen to work.
        List {
            FileTreeRows(
                nodes: FileTree.build(files),
                open: open,
                viewed: viewed?.states ?? [:],
                comments: ReviewThreadPlacement.openCounts(threads),
                current: place.path,
                choose: { place.path = $0 }
            )
        }
        // Inset rather than sidebar: the sidebar style draws an edge shadow
        // down its trailing side, which fell across the diff beside it.
        // Plain rather than inset: the inset style gives every row
        // twenty-two points of leading of its own, which on a tree six
        // levels deep was more than a third of what the indentation cost
        // -- and it does not offer to give them back.
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(width: sidebar.width)
    }

    /// The divider between the file list and the diff, which can be moved.
    ///
    /// A hairline is not something anybody can hit, so the grab area is
    /// wider than the line it draws and sits over it: the divider stays a
    /// hairline and the target is eight points across.
    ///
    /// The width is kept here while it is being dragged and written to the
    /// settings when the hand comes off. Writing on every frame would put
    /// sixty values a second into preferences for one decision.
    private var handle: some View {
        SidebarHandle(width: sidebar.width) { chosen in
            sidebar.width = chosen
            setSidebarWidth?(chosen)
        }
    }



    private var diffs: some View {
        // The width is measured and handed down: inside a horizontal scroll
        // view `maxWidth: .infinity` resolves to the content's own width, so
        // every band stopped at the end of its longest line and a diff of
        // short lines sat in a narrow column of colour.
        GeometryReader { proxy in
            ScrollView(.vertical) {
                // Pinned headers: the file being read keeps its name at the
                // top of the column, and the next file's header pushes it
                // off as it arrives. Without it a long patch leaves you
                // scrolling through code with nothing saying which file it
                // belongs to.
                LazyVStack(
                    alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(files) { file in
                        Section {
                            fileBody(file, width: proxy.size.width)
                        } header: {
                            fileHeader(file)
                        }
                        .id(file.path)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollPosition(id: $place.path, anchor: .top)
        }
    }

    /// The line that stays at the top while its file is being read.
    ///
    /// Opaque, and that is not decoration: a pinned header over a scroll
    /// view shows whatever is passing underneath it unless it brings its
    /// own background.
    private func fileHeader(_ file: ChangedFile) -> some View {
        let state = viewed?.state(file.path) ?? .unviewed
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let viewed {
                    Button { tick(file, viewed) } label: {
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
            .padding(.vertical, 6)

            Divider()
        }
        .background(.background)
    }

    /// Ticks a file off and, where that folded away the one being read,
    /// moves on to the top of the next. `DiffNavigation` decides where.
    private func tick(_ file: ChangedFile, _ viewed: ViewedFiles) {
        let folding = !viewed.state(file.path).isFolded
        viewed.toggle(file.path)

        guard let destination = DiffNavigation.destination(
            ticking: file.path, folding: folding, showing: place.path, in: files
        ) else { return }

        withAnimation(.easeOut(duration: 0.2)) { place.path = destination }
    }

    private func fileBody(_ file: ChangedFile, width: CGFloat) -> some View {
        let state = viewed?.state(file.path) ?? .unviewed
        return VStack(alignment: .leading, spacing: 6) {
            // A ticked file keeps its header and its place, and folds the
            // patch away. Folded rather than hidden: the point of the tick
            // is "done with this for now", not "never show me again".
            if state.isFolded {
                Text("Viewed \u{2014} click the tick to unfold it again")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else if let patch = file.patch {
                let mine = threads.filter { $0.path == file.path }
                let stranded = ReviewThreadPlacement.unplaceable(mine, in: file.path)
                if !stranded.isEmpty {
                    OutdatedThreadsView(threads: stranded)
                }

                // Nothing in here scrolls sideways: a line too long for
                // the column wraps. That is what finally made this simple
                // -- no scroll views inside a file, nothing to keep in
                // step, and a row whose two halves share one height.
                // Two columns only where there are two sides. A file that
                // was added has no old version, so the left column would be
                // half a window of nothing and every line of the new file
                // would be squeezed into the other half to face it.
                switch layout {
                case .sideBySide where !DiffSideBySide.isOneSided(patch):
                    SideBySidePatch(
                        patch: patch,
                        language: file.language,
                        available: width,
                        fontSize: fontSize,
                        showsLineNumbers: showsLineNumbers,
                        threads: ReviewThreadPlacement.placed(mine, in: file.path)
                    )
                    .padding(.vertical, 6)
                case .unified, .sideBySide:
                    PatchLines(
                        patch: patch,
                        language: file.language,
                        fontSize: fontSize,
                        showsLineNumbers: showsLineNumbers,
                        threads: ReviewThreadPlacement.placed(mine, in: file.path),
                        column: width
                    )
                    .padding(.vertical, 6)
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
    var fontSize: Double = Settings.defaultDiffFontSize
    var showsLineNumbers: Bool = true
    /// The conversations to draw among the lines they hang on.
    var threads: [ReviewThread] = []
    /// How wide the column is, for the prose among the code. The patch
    /// itself may be wider and scroll; a comment keeps the column's width
    /// so it reads as prose rather than as a very long line.
    var column: CGFloat = 400

    private var lines: [Line] {
        let numbers = showsLineNumbers ? DiffLineNumbers.read(patch) : []
        // One column keeps the order the patch was written in -- that order
        // is what a unified diff is -- but the words it marks are found the
        // same way as in two columns, so the two agree.
        let marks = DiffCache.shared.emphasis(in: patch)
        // Numbered and marked over the whole patch before the slice: both
        // depend on what came earlier in the file, and a stretch measured
        // on its own would start counting from one.
        return patch.components(separatedBy: "\n").enumerated().map { index, text in
            Line(
                id: index,
                text: text,
                number: index < numbers.count ? numbers[index] : .none,
                emphasis: index < marks.count ? marks[index] : []
            )
        }
    }

    /// Which conversations hang off which line of the patch.
    private var anchors: [Int: [ReviewThread]] {
        guard !threads.isEmpty else { return [:] }
        return ReviewThreadAnchors.unified(patch: patch, threads: threads)
    }

    /// Set once for the whole file, so the code keeps one left edge rather
    /// than stepping right where the numbers reach three digits.
    private var gutterDigits: Int {
        showsLineNumbers ? DiffLineNumbers.width(of: DiffLineNumbers.read(patch)) : 0
    }

    var body: some View {
        let digits = gutterDigits
        let anchors = anchors
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                row(line, digits: digits)
                if let here = anchors[line.id] {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(here) { ReviewThreadView(thread: $0) }
                    }
                    .frame(width: column, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ line: Line, digits: Int) -> some View {
        let kind = DiffLineKind(line: line.text)
        let split = DiffWords.split(line.text, emphasis: line.emphasis)
        return HStack(alignment: .top, spacing: 0) {
            if showsLineNumbers {
                gutter(line.number, digits: digits)
            }

            // The marker in a column of its own, so a line too long for the
            // page wraps under its code rather than where a `+` would be.
            Text(verbatim: split.marker)
                .font(.system(size: fontSize).monospaced())
                .foregroundStyle(.secondary)
                .frame(width: markerWidth, alignment: .leading)

            CodeText(
                source: split.body,
                // A hunk header is not code, and the marker column at the
                // start of every other line would have the highlighter
                // reading `-` as punctuation before a keyword. Colour the
                // code, not the diff.
                language: kind == .hunk ? nil : language,
                font: .system(size: fontSize).monospaced(),
                emphasis: split.emphasis,
                emphasisTint: kind.emphasis
            )
            .foregroundStyle(kind.textTint)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        // In a plain rectangle: a bare colour background rounds its
        // corners on this system, which made every added and removed line
        // look like a pill.
        .background(kind.background, in: Rectangle())
        // One element per line rather than one per coloured token.
        // Resolving the attributed text of every token is where nearly all
        // of the layout time went on a large diff: a thousand lines of
        // code made thousands of accessibility nodes, each walked again on
        // every frame of a scroll.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line.text))
    }

    /// The two numbers, old then new, before the line itself.
    ///
    /// Plain `Text` rather than the selectable kind the code uses, so
    /// copying a passage out of the diff copies the code and not a column
    /// of numbers down its left-hand side.
    ///
    /// Padded to a set number of digits with figure spaces rather than laid
    /// out with fixed frames: in a monospaced font that is what lines the
    /// columns up, and it costs no measurement.
    private func gutter(_ number: DiffLineNumber, digits: Int) -> some View {
        Text(verbatim: Self.pad(number.old, to: digits) + " " + Self.pad(number.new, to: digits))
            .font(.system(size: fontSize).monospaced())
            .foregroundStyle(.tertiary)
            .padding(.leading, 12)
            .padding(.trailing, 8)
    }

    /// One character, plus the room either side of it.
    private var markerWidth: CGFloat {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            .maximumAdvancement.width + 10
    }

    static func pad(_ number: Int?, to digits: Int) -> String {
        let text = number.map(String.init) ?? ""
        return String(repeating: " ", count: max(0, digits - text.count)) + text
    }

    private struct Line: Identifiable {
        let id: Int
        let text: String
        let number: DiffLineNumber
        let emphasis: [ChangedRange]
    }
}

/// What a line of a patch is, and how it is drawn.
///
/// At file scope rather than inside one of the two layouts: both read the
/// same patch lines, and a second copy of this would be the one that
/// drifts.
enum DiffLineKind {
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

    /// The stronger band behind the words that actually changed, where the
    /// line opposite is close enough to say which those are.
    ///
    /// The row's own colour at roughly twice the strength: a third colour
    /// would read as a third kind of change, and the point is "this part of
    /// this change", not something new.
    var emphasis: Color {
        switch self {
        case .added: .green.opacity(0.3)
        case .removed: .red.opacity(0.3)
        case .hunk, .context: .clear
        }
    }

    /// Only the hunk header is recoloured outright; added and removed lines
    /// keep their syntax colours and are told apart by the band behind them.
    var textTint: Color {
        switch self {
        case .hunk: Color(nsColor: .secondaryLabelColor)
        case .added, .removed, .context: Color(nsColor: .labelColor)
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
    @Published private(set) var shut: Set<String> = []

    func isOpen(_ path: String) -> Bool { !shut.contains(path) }

    func toggle(_ path: String) {
        if shut.contains(path) { shut.remove(path) } else { shut.insert(path) }
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
    /// What each file still has open from the review, by path. The list is
    /// what somebody scans to decide where to go next, and an unanswered
    /// remark is the best reason there is to go somewhere.
    var comments: [String: ReviewThreadPlacement.OpenComments] = [:]
    /// The file the diff is showing, which this list marks.
    var current: String?
    /// What to do when one is picked.
    var choose: (String) -> Void = { _ in }

    var body: some View {
        ForEach(FileTree.rows(nodes, shut: open.shut)) { row in
            switch row.node {
            // Buttons rather than tap gestures. A list row swallows a
            // plain gesture: with `onTapGesture` on these, clicking a file
            // neither marked it nor moved the diff, and clicking a folder
            // did not even fold it.
            case .file(let file):
                Button { choose(file.path) } label: {
                    fileRow(file, depth: row.depth)
                }
                .buttonStyle(.plain)
            case .folder(let folder):
                Button { open.toggle(folder.path) } label: {
                    folderRow(folder, depth: row.depth)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// How far one level is set in.
    ///
    /// Four points. Measured at ten, six levels of a PHP module spent
    /// sixty of the list's two hundred and sixty on indentation alone; at
    /// four it is twenty-four. A level still reads as a level -- the
    /// triangle and the grey of a folder's name say more about the
    /// hierarchy than the distance does, and in this list the distance was
    /// being paid for out of the file names.
    private static let step: CGFloat = 4
    /// Room for the triangle, so a file sits under its folder's name
    /// rather than under its triangle.
    private static let twistWidth: CGFloat = 12
    /// What the list holds back at its leading edge whatever it is told.
    ///
    /// `listRowInsets` does not give it back and neither does
    /// `contentMargins`, so the rows are pulled back over it. It is worth
    /// about two characters of every file name.
    private static let listInset: CGFloat = 10

    private func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * Self.step }

    private func fileRow(_ file: ChangedFile, depth: Int) -> some View {
        let state = viewed[file.path] ?? .unviewed
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Spacer()
                .frame(width: indent(depth) + Self.twistWidth)
            // Only where it says something. Nearly every file in a review
            // is modified, so a pencil beside all of them is a column of
            // one repeated symbol -- and in a list this narrow that column
            // costs as much as two levels of indentation.
            if file.change != .modified {
                Image(systemName: file.change.symbolName)
                    .foregroundStyle(.secondary)
                    .help(file.change.label)
            }
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
            if let open = comments[file.path] {
                badge(open)
            }
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
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .padding(.leading, -Self.listInset)
        // Drawn here rather than left to the list, which would not draw it
        // at all for a flat row of mixed kinds.
        .background(
            file.path == current ? Color.secondary.opacity(0.22) : .clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .help(file.path)
    }

    /// How much is open, for a file or for a whole folder.
    ///
    /// Blue because the other marks in this row are spoken for: green and
    /// red are the size of the change, green and orange are whether it has
    /// been read. An unanswered remark is none of those.
    private func badge(_ open: ReviewThreadPlacement.OpenComments) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "bubble.left.fill")
            Text(verbatim: "\(open.conversations)").monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.blue)
        .help(open.label)
    }

    /// What a folder holds, so a shut one still says there is something
    /// inside worth opening.
    private func folded(_ folder: FileTree.Folder) -> ReviewThreadPlacement.OpenComments? {
        let inside = folder.files.compactMap { comments[$0.path] }
        guard !inside.isEmpty else { return nil }
        return ReviewThreadPlacement.OpenComments(
            conversations: inside.reduce(0) { $0 + $1.conversations },
            comments: inside.reduce(0) { $0 + $1.comments }
        )
    }

    private func folderRow(_ folder: FileTree.Folder, depth: Int) -> some View {
        HStack(spacing: 6) {
            Spacer()
                .frame(width: indent(depth))
            Image(systemName: open.isOpen(folder.path) ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: Self.twistWidth, alignment: .leading)
            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            if let open = folded(folder) {
                badge(open)
            }
            Text(verbatim: "\(folder.files.count)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.leading, -Self.listInset)
        .help(folder.path)
        // The whole row, not just the triangle: a folder's name is the
        // thing anybody aims at, and it is the wider target by far.
        .contentShape(Rectangle())
        .pointerStyle(.link)
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

/// Where the diff is being read, for as long as it is open.
///
/// View-local state without `@State`, whose macro ships only with Xcode.
@MainActor
final class DiffPlace: ObservableObject {
    /// The file at the top of the column.
    ///
    /// Written by scrolling it and by the list beside it, which is what
    /// makes the two follow each other.
    @Published var path: String?
}

/// How wide the file list beside the diff is.
///
/// View-local state without `@State`, whose macro ships only with Xcode.
@MainActor
final class SidebarWidth: ObservableObject {
    @Published var width: CGFloat = Settings.defaultDiffSidebarWidth
}

/// The edge between the file list and the diff, which can be moved.
///
/// Its own view, holding its own state, so that dragging it redraws the
/// line and nothing else. Kept on the overlay, the proposed width redrew
/// the whole diff on every frame of the drag for a number only the line
/// was waiting on.
private struct SidebarHandle: View {
    /// Where the edge is now. It does not move until the hand comes off.
    let width: CGFloat
    let commit: (CGFloat) -> Void

    @StateObject private var drag = HandleDrag()

    var body: some View {
        // A filled shape rather than `Color.clear`, whose hit testing is
        // not something to lean on: the first version of this was a clear
        // strip marked only by a hairline, and it could not be caught with
        // a mouse at all. Nearly-invisible grey is a surface either way,
        // and it shows itself under the pointer so there is something to
        // aim at.
        Rectangle()
            .fill(Color.secondary.opacity(drag.isHovering ? 0.22 : 0.001))
            .frame(width: Self.width)
            // Drawn, not felt: the line says where the edge is, the strip
            // around it is what the hand catches.
            .overlay(Divider().allowsHitTesting(false))
            .contentShape(Rectangle())
            // Not asked during a drag: the strip follows the pointer a
            // frame behind, so the answer keeps changing and the highlight
            // blinks all the way across.
            .onHover { if drag.proposed == nil { drag.isHovering = $0 } }
            .pointerStyle(.columnResize)
            // While the hand is on it the line goes where the pointer
            // goes, and the diff behind it stays where it was. Every line
            // of the diff wraps to its column, so changing that column on
            // every frame re-wraps the whole file sixty times a second --
            // which is not resizing, it is flickering.
            .offset(x: (drag.proposed ?? width) - width)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        drag.isHovering = true
                        drag.proposed = Settings.clampedSidebarWidth(
                            width + gesture.translation.width
                        )
                    }
                    .onEnded { _ in
                        if let proposed = drag.proposed { commit(proposed) }
                        drag.proposed = nil
                    }
            )
    }

    /// Twelve points, centred on the line: six either side is what a mouse
    /// can find without aiming. The strip is invisible until the pointer
    /// is over it, so the width costs the diff nothing to look at.
    private static let width: CGFloat = 12
}

/// What the edge is doing, watched by the edge alone.
@MainActor
private final class HandleDrag: ObservableObject {
    @Published var proposed: CGFloat?
    @Published var isHovering = false
}
