import SwiftUI

/// Conversations down the right-hand side of a file, each on the height of
/// the line it is about.
///
/// They used to be drawn between the lines, which cost the diff its shape:
/// a file with three conversations was twice as long as its own patch, and
/// opening one moved the code out from under the reader. At the margin a
/// card costs width instead of height, and the only thing a card can move
/// is another card.
public enum MarginCards {
    /// Wide enough for prose at the caption size, narrow enough to leave
    /// a usable column of code beside it in a window somebody has not
    /// maximised.
    public static let width: CGFloat = 282
    public static let gap: CGFloat = 8

    /// Where each card is drawn, given where its line is and how tall the
    /// card turned out to be.
    ///
    /// A card wants to be level with its line and gives that up only to
    /// the card above it -- never the other way round. So the order down
    /// the column is the order down the file, two conversations three
    /// lines apart do not overlap, and a card that opens pushes its
    /// neighbours down rather than moving the code.
    ///
    /// Anchors are expected in the order they appear in the file. Out of
    /// order they would still not overlap, but a card would be placed
    /// below a line that comes after it, which is a lie about what it is
    /// attached to.
    public static func place(
        anchors: [CGFloat],
        heights: [CGFloat],
        gap: CGFloat = gap,
        from top: CGFloat = 0
    ) -> [CGFloat] {
        var tops: [CGFloat] = []
        tops.reserveCapacity(anchors.count)
        var floor = top
        for (index, anchor) in anchors.enumerated() {
            let at = max(anchor, floor)
            tops.append(at)
            floor = at + (index < heights.count ? heights[index] : 0) + gap
        }
        return tops
    }

    /// How tall the column has to be to hold what is in it.
    ///
    /// A file whose last conversation hangs off its last line would
    /// otherwise have the card cut off by the end of the patch.
    public static func height(tops: [CGFloat], heights: [CGFloat]) -> CGFloat {
        zip(tops, heights).map(+).max() ?? 0
    }
}

/// One card at the margin: something written about a line, or the box in
/// which something is being written.
struct MarginEntry: Identifiable {
    enum Kind {
        case thread(ReviewThread)
        /// A remark in this draft that starts its own conversation.
        case remark(DraftComment)
        /// The editor, open on a bare line. A reply is drawn inside the
        /// conversation it answers, so it needs no card of its own.
        case editor(line: Int, side: ReviewThread.Side)
    }

    let id: String
    let kind: Kind

    /// What the patch reports the position of. The same string on both
    /// sides, so neither has to know how the other is laid out.
    static func key(forThread id: String) -> String { "t:\(id)" }
    static func key(forRemark id: UUID) -> String { "r:\(id.uuidString)" }
    static let editorKey = "editor"
}

/// Where each card's line sits, as the patch measured it.
///
/// A preference rather than a value passed down, because only the rows
/// know where they ended up: the measurement travels up from them, and
/// the column that draws the cards is their sibling, not their parent.
struct MarginAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// How tall each card turned out to be, which is the other half of the
/// placement and is known only after it has been drawn.
struct MarginHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// What a patch hands back about where its rows are.
@MainActor
final class MarginAnchors: ObservableObject {
    @Published var tops: [String: CGFloat] = [:]
}

@MainActor
final class MarginHeights: ObservableObject {
    @Published var heights: [String: CGFloat] = [:]
}

extension View {
    /// Reports this row's top edge under every key it carries.
    ///
    /// A background rather than an overlay: a row that is measured must
    /// not stop being clickable, and the gutter under the pointer is a
    /// button.
    func marginAnchor(_ keys: [String], in space: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MarginAnchorKey.self,
                    value: keys.isEmpty
                        ? [:]
                        : Dictionary(
                            uniqueKeysWithValues: keys.map {
                                ($0, proxy.frame(in: .named(space)).minY)
                            }
                        )
                )
            }
        )
    }
}

/// The column itself.
struct MarginColumn: View {
    let entries: [MarginEntry]
    /// Where each entry's line is, in the space both columns share.
    let anchors: [String: CGFloat]
    let path: String
    var writing: DraftWriting?
    @ObservedObject var target: DraftTarget
    /// What the draft answers each conversation with.
    let replies: (ReviewThread) -> [DraftComment]

    @StateObject private var measured = MarginHeights()

    var body: some View {
        let tops = placed
        ZStack(alignment: .topLeading) {
            // A shape rather than nothing: the column has to claim its
            // height even though everything in it is positioned by hand.
            Color.clear
                .frame(height: MarginCards.height(tops: tops, heights: heights))

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                card(entry)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MarginHeightKey.self,
                                value: [entry.id: proxy.size.height]
                            )
                        }
                    )
                    .offset(y: index < tops.count ? tops[index] : 0)
            }
        }
        .frame(width: MarginCards.width, alignment: .topLeading)
        .onPreferenceChange(MarginHeightKey.self) { [measured] new in
            MainActor.assumeIsolated { measured.heights = new }
        }
    }

    private var heights: [CGFloat] {
        // Until a card has been drawn once there is nothing to ask about
        // its height. A guess that is too small only ever means two cards
        // overlap for one frame, which is the frame before the real
        // measurement arrives.
        entries.map { measured.heights[$0.id] ?? 64 }
    }

    private var placed: [CGFloat] {
        MarginCards.place(
            anchors: entries.map { anchors[$0.id] ?? 0 },
            heights: heights
        )
    }

    @ViewBuilder
    private func card(_ entry: MarginEntry) -> some View {
        Group {
            switch entry.kind {
            case .thread(let thread):
                ReviewThreadView(
                    thread: thread,
                    writing: writing,
                    replies: replies(thread),
                    target: target,
                    inMargin: true
                )
            case .remark(let comment):
                if let writing {
                    DraftRemarkView(comment: comment, writing: writing, target: target)
                }
            case .editor(let line, let side):
                if let writing {
                    DraftEditorView(
                        path: path, line: line, side: side,
                        writing: writing, target: target
                    )
                }
            }
        }
        .frame(width: MarginCards.width - 20, alignment: .leading)
        // Its own height, not the column's. In a `ZStack` every child is
        // offered the stack's full height, and the rule down the left of
        // a conversation is a `Rectangle`, which takes whatever it is
        // offered -- so without this a single card grew to the height of
        // the column, was measured at that height, and grew the column.
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        .padding(.leading, 10)
    }
}

extension MarginEntry {
    /// Everything that belongs at one file's margin, in the order the
    /// lines run down the file.
    ///
    /// Ordered by line rather than by where the rows were measured to be:
    /// the order has to be settled before the first frame is drawn, and a
    /// measurement is not. They agree anyway -- a conversation about line
    /// twelve is drawn below one about line four.
    @MainActor
    static func all(
        threads: [ReviewThread],
        draft: [DraftComment],
        editing target: DraftTarget,
        path: String
    ) -> [MarginEntry] {
        var entries: [(line: Int, entry: MarginEntry)] = []

        for thread in threads {
            entries.append((
                thread.anchorLine ?? thread.line ?? 0,
                MarginEntry(id: key(forThread: thread.id), kind: .thread(thread))
            ))
        }

        // Replies are drawn inside the conversation they answer, so only
        // the remarks that start one get a card.
        for comment in draft where !comment.isReply {
            entries.append((
                comment.line,
                MarginEntry(id: key(forRemark: comment.id), kind: .remark(comment))
            ))
        }

        if let line = target.line, target.replyingTo == nil, target.editing == nil {
            entries.append((
                line,
                MarginEntry(id: editorKey, kind: .editor(line: line, side: target.side))
            ))
        }

        return entries
            .sorted { ($0.line, $0.entry.id) < ($1.line, $1.entry.id) }
            .map(\.entry)
    }
}

/// One file: its code, and its conversations beside it.
///
/// A view of its own because the two halves have to agree about where the
/// lines are, and that agreement is a measurement held between them --
/// which needs somewhere to live that outlasts a redraw.
struct FileSheet: View {
    let file: ChangedFile
    let patch: String
    let width: CGFloat
    let layout: DiffLayout
    let fontSize: Double
    let showsLineNumbers: Bool
    /// The conversations that found a line in this patch.
    let threads: [ReviewThread]
    let draft: [DraftComment]
    var writing: DraftWriting?
    @ObservedObject var target: DraftTarget

    @StateObject private var anchors = MarginAnchors()

    private var entries: [MarginEntry] {
        MarginEntry.all(
            threads: threads, draft: draft, editing: target, path: file.path
        )
    }

    /// The margin takes its width from the code, and only where there is
    /// something to put in it. A file nobody said anything about reads
    /// exactly as wide as it always did.
    private var codeWidth: CGFloat {
        entries.isEmpty ? width : max(width - MarginCards.width, Self.narrowestCode)
    }

    private var space: String { "file:\(file.path)" }

    var body: some View {
        let entries = entries
        HStack(alignment: .top, spacing: 0) {
            code
                .frame(width: codeWidth, alignment: .leading)

            if !entries.isEmpty {
                MarginColumn(
                    entries: entries,
                    anchors: anchors.tops,
                    path: file.path,
                    writing: writing,
                    target: target,
                    replies: { thread in
                        draft
                            .filter { $0.replyTo == thread.id }
                            .sorted { $0.writtenAt < $1.writtenAt }
                    }
                )
            }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(MarginAnchorKey.self) { [anchors] new in
            MainActor.assumeIsolated { anchors.tops = new }
        }
    }

    @ViewBuilder
    private var code: some View {
        // Two columns only where there are two sides. A file that was
        // added has no old version, so the left column would be half a
        // window of nothing.
        switch layout {
        case .sideBySide where !DiffSideBySide.isOneSided(patch):
            SideBySidePatch(
                patch: patch,
                language: file.language,
                available: codeWidth,
                fontSize: fontSize,
                showsLineNumbers: showsLineNumbers,
                threads: threads,
                path: file.path,
                draft: draft,
                writing: writing,
                target: target,
                space: space
            )
            .padding(.vertical, 6)
        case .unified, .sideBySide:
            PatchLines(
                patch: patch,
                language: file.language,
                fontSize: fontSize,
                showsLineNumbers: showsLineNumbers,
                threads: threads,
                path: file.path,
                draft: draft,
                writing: writing,
                target: target,
                space: space
            )
            .padding(.vertical, 6)
        }
    }

    /// Below this the code column is not worth reading, and the margin
    /// has to give way instead -- which it does by overlapping nothing:
    /// the window simply scrolls.
    private static let narrowestCode: CGFloat = 320
}
