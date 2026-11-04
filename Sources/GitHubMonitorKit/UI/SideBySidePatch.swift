import AppKit
import SwiftUI

/// A patch in two columns: the old file on the left, the new on the right.
///
/// Nothing here scrolls sideways. A line too long for its column wraps,
/// which is what finally made this layout simple: there are no scroll
/// views inside a file, nothing to keep in step, and the two sides of a
/// row share one height because they are one row.
///
/// Before that the file was cut into a piece per hunk and a piece per
/// comment, each piece a pair of scroll views kept level by passing
/// positions around -- and a review of forty files became hundreds of
/// scroll views sending one another messages.
///
/// The divider sits at the middle, always, so every file opens looking
/// the same.
struct SideBySidePatch: View {
    let patch: String
    let language: CodeLanguage?
    /// The width the two columns share.
    let available: CGFloat
    var fontSize: Double = Settings.defaultDiffFontSize
    var showsLineNumbers: Bool = true
    /// The conversations to draw among the lines they hang on.
    var threads: [ReviewThread] = []
    /// Which file this is, which a remark has to name.
    var path: String = ""
    /// Remarks written about this file but not sent.
    var draft: [DraftComment] = []
    /// How to write one. Nil leaves the diff a reader.
    var writing: DraftWriting?

    /// The whole file, where it has been fetched, for the lines between
    /// the hunks. Nil leaves the patch as GitHub sent it.
    var content: FileContent?
    var isFetchingContent = false
    /// Asks for the file. Nil leaves the gaps closed and unoffered.
    var fetchContent: (() -> Void)?
    /// Every gap open at once, for a file being read rather than
    /// reviewed. The rows that offer the gaps go with it: there is
    /// nothing left for them to offer.
    var showsWholeFile = false

    /// Where a remark is being written. Handed in rather than owned:
    /// it belongs to the review, not to whichever file is on screen.
    @ObservedObject var target: DraftTarget
    @StateObject private var hovered = HoveredRow()
    @StateObject private var expansion = Expansion()

    var body: some View {
        let width = columnWidth
        // Lazy, for the same reason the single column is: a long file
        // built every row on every pass, and most of them were nowhere
        // near the screen.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row.kind {
                case .gap(let gap):
                expanded(gap, width: width)
            case .threads(let here):
                    // Prose belongs to the row, not to a column: it is as
                    // wide as the pair of them.
                    conversations(here)
                        .frame(width: width * 2 + Self.dividerWidth, alignment: .leading)
                        .zIndex(here.contains { target.isReplying(to: $0.id) } ? 1 : 0)
                default:
                    // Both sides in one row, so a line that wraps on one
                    // side takes the other down with it and the two columns
                    // cannot drift apart.
                    HStack(alignment: .top, spacing: 0) {
                        cell(row, side: .old, width: width)
                        Divider().frame(width: Self.dividerWidth)
                        cell(row, side: .new, width: width)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if let writing {
                        drafting(row, writing: writing)
                            .frame(width: width * 2 + Self.dividerWidth, alignment: .leading)
                            .zIndex(isDrafting(row) ? 1 : 0)
                    }
                }
            }
        }
        // What was pressed before the file was here, carried out now that
        // it is. Without this the first press only fetched, and a second
        // was needed to open what had already arrived.
        .onChange(of: content) {
            guard content?.lines != nil else { return }
            expansion.applyPending(gaps)
        }
        .onReceive(NotificationCenter.default.publisher(for: .diffOpenDraft)) { _ in
            guard writing != nil, target.line == nil, target.replyingTo == nil else { return }
            guard let place = rows.lazy.compactMap({ self.place(of: $0) }).first
            else { return }
            target.open(path: path, line: place.line, side: place.side)
        }
    }

    /// The conversations hanging off one row, and whatever this draft
    /// has to say about it.
    ///
    /// The same shape as the one column has. Reviewing from two columns
    /// was a reader's seat for a while, which it should not have been:
    /// which layout suits a patch is a judgement about the patch, not
    /// about whether you intend to say anything.
    private func conversations(_ here: [ReviewThread]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(here) { thread in
                ReviewThreadView(
                    thread: thread,
                    writing: writing,
                    replies: draft
                        .filter { $0.replyTo == thread.id }
                        .sorted { $0.writtenAt < $1.writtenAt },
                    target: target,
                    isReplying: target.isReplying(to: thread.id)
                )
            }
        }
    }

    /// What a row carries of the review being written.
    @ViewBuilder
    private func drafting(_ row: Row, writing: DraftWriting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(remarks(on: row)) { comment in
                DraftRemarkView(comment: comment, writing: writing, target: target)
            }
            if let place = place(of: row), target.isOpen(path: path, line: place.line, side: place.side) {
                DraftEditorView(
                    path: path, line: place.line, side: place.side,
                    writing: writing, target: target
                )
            }
        }
    }

    private func remarks(on row: Row) -> [DraftComment] {
        guard case .pair(let left, let right) = row.kind else { return [] }
        return draft.filter { comment in
            guard !comment.isReply else { return false }
            return comment.side == .new
                ? comment.line == right?.number
                : comment.line == left?.number
        }
    }

    /// Whether the box is open on this row.
    ///
    /// Worth knowing only so the row can be lifted above the ones under
    /// it. The list of names floats out of the box and over the code,
    /// which is where it belongs -- but a stack paints its children in
    /// order, and overflowing the bounds does not change the order. The
    /// rows below were therefore painted on top of the half of the list
    /// that had left the box, which is what let the diff show through it.
    private func isDrafting(_ row: Row) -> Bool {
        guard let place = place(of: row) else { return false }
        return target.isOpen(path: path, line: place.line, side: place.side)
    }

    /// Which line of which file a remark on this row would be about.
    private func place(of row: Row) -> (line: Int, side: ReviewThread.Side)? {
        guard case .pair(let left, let right) = row.kind else { return nil }
        if let new = right?.number { return (new, .new) }
        if let old = left?.number { return (old, .old) }
        return nil
    }

    /// The line's number, which turns into a plus under the pointer.
    ///
    /// One gutter per column, so which of them the pointer is in is part
    /// of what is remembered -- the same line can be numbered on both
    /// sides, and only the one being pointed at should offer itself.
    @ViewBuilder
    private func gutter(_ row: Row, side: ReviewThread.Side) -> some View {
        let number = number(row, side: side)
        let key = "\(row.id)-\(side.rawValue)"
        let isHere = hovered.holds(key)

        if writing != nil, let number {
            Button {
                target.open(path: path, line: number, side: side)
            } label: {
                Text(verbatim: PatchLines.pad(number, to: gutterDigits))
                    .font(font)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .opacity(isHere ? 0 : 1)
                    .overlay(alignment: .trailing) {
                        if isHere {
                            Image(systemName: "plus")
                                .font(.system(size: max(8, fontSize - 3), weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: fontSize + 5, height: fontSize + 5)
                                .background(Ink.blue, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .padding(.leading, 12)
                    .frame(width: gutterWidth, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovered.set(key, $0) }
            .help("Write a remark about this line")
        } else {
            Text(verbatim: PatchLines.pad(number, to: gutterDigits))
                .font(font)
                .foregroundStyle(.tertiary)
                .padding(.leading, 12)
                .frame(width: gutterWidth, alignment: .topLeading)
        }
    }

    /// One side of one row: its number, its marker and its code.
    private func cell(_ row: Row, side: ReviewThread.Side, width: CGFloat) -> some View {
        let text = self.text(row, side: side)
        let kind = text.map { DiffLineKind(line: $0.whole) }
        return HStack(alignment: .top, spacing: 0) {
            if showsLineNumbers {
                gutter(row, side: side)
            }

            if let text {
                // The marker in a column of its own, so what wraps lines up
                // under the code rather than where a `+` would be.
                Text(verbatim: text.marker)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .frame(width: markerWidth, alignment: .leading)

                CodeText(
                    source: text.body,
                    language: row.isHunk ? nil : language,
                    insideComment: text.insideComment,
                    font: font,
                    emphasis: text.emphasis,
                    emphasisTint: kind?.emphasis ?? .clear
                )
                    .foregroundStyle(kind?.textTint ?? Color(nsColor: .labelColor))
                    .padding(.trailing, 12)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 1)
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(kind?.background ?? Self.absent, in: Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text?.whole ?? ""))
    }

    // MARK: - What a row holds

    private struct Piece {
        let whole: String
        let marker: String
        let body: String
        let emphasis: [ChangedRange]
        /// Whether the line above this one, on this side of the patch,
        /// left a block comment open.
        var insideComment: Bool = false
    }

    private func text(_ row: Row, side: ReviewThread.Side) -> Piece? {
        switch row.kind {
        case .hunk(let line):
            let halves = DiffSideBySide.halves(ofHunk: line)
            let whole = side == .old ? halves.old : halves.new
            return Piece(whole: whole, marker: "", body: whole, emphasis: [])
        case .note(let line):
            // Whichever file it is about, the note is short enough to say
            // on both sides and the row needs the same height either way.
            return Piece(whole: line, marker: "", body: line, emphasis: [])
        // Neither is a line of the patch: one is a conversation, the
        // other the app offering code the patch does not carry.
        case .gap:
            return nil
        case .threads:
            return nil
        case .pair(let left, let right):
            guard let cell = side == .old ? left : right else { return nil }
            let split = DiffWords.split(cell.text, emphasis: cell.emphasis)
            return Piece(
                whole: cell.text, marker: split.marker,
                body: split.body, emphasis: split.emphasis,
                insideComment: DiffCache.shared
                    .comments(in: patch, language: language)
                    .isInsideComment(line: cell.number, side: side)
            )
        }
    }

    private func number(_ row: Row, side: ReviewThread.Side) -> Int? {
        guard case .pair(let left, let right) = row.kind else { return nil }
        return (side == .old ? left : right)?.number
    }

    // MARK: - Measuring

    /// Half of what is on offer, less half the divider.
    private var columnWidth: CGFloat {
        max((available - Self.dividerWidth) / 2, Self.narrowest)
    }

    /// As wide as the widest number in the file, so the code keeps one left
    /// edge down the column.
    private var gutterDigits: Int {
        guard showsLineNumbers else { return 0 }
        return max(String(DiffCache.shared.rows(of: patch).reduce(0) { widest, row in
            guard case .pair(let left, let right) = row else { return widest }
            return max(widest, left?.number ?? 0, right?.number ?? 0)
        }).count, 1)
    }

    private var gutterWidth: CGFloat {
        guard showsLineNumbers else { return 0 }
        return CGFloat(gutterDigits) * advance + Self.gutterPadding
    }

    /// One character, plus the room either side of it.
    private var markerWidth: CGFloat { advance + 10 }

    private var font: Font { .system(size: fontSize).monospaced() }

    private var advance: CGFloat {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).maximumAdvancement.width
    }

    // MARK: - Rows

    /// Every row of the file, in order, with the conversations among them.
    private var rows: [Row] {
        let patchRows = DiffCache.shared.rows(of: patch)
        let anchors = ReviewThreadAnchors.sideBySide(rows: patchRows, threads: threads)
        // Matched to the hunk each one sits above rather than to a row
        // index: a removal and the addition answering it are two lines of
        // the patch and one row here, so the two do not count alike. What
        // a hunk header states is a line number, and a gap knows the line
        // number it ends at.
        var pending = gaps
        var result: [Row] = []

        for (index, row) in patchRows.enumerated() {
            if case .hunk(let text) = row,
                let starts = DiffLineNumbers.starts(ofHunk: text),
                let found = pending.firstIndex(where: { $0.last + 1 == starts.new }) {
                result.append(Row(id: result.count, kind: .gap(pending.remove(at: found))))
            }
            switch row {
            case .hunk(let text): result.append(Row(id: result.count, kind: .hunk(text)))
            case .note(let text): result.append(Row(id: result.count, kind: .note(text)))
            case .pair(let left, let right):
                result.append(Row(id: result.count, kind: .pair(left, right)))
            }
            if let here = anchors[index] {
                result.append(Row(id: result.count, kind: .threads(here)))
            }
        }
        // Whatever is left is below the last hunk.
        for gap in pending { result.append(Row(id: result.count, kind: .gap(gap))) }
        return result
    }

    /// Where the patch is silent, if the file is here to say.
    private var gaps: [DiffGaps.Gap] {
        guard fetchContent != nil else { return [] }
        return DiffCache.shared.gaps(
            in: patch, fileLines: content?.lines?.count ?? 0
        )
    }

    /// The lines already opened at a gap, and a row offering what is left.
    @ViewBuilder
    private func expanded(_ gap: DiffGaps.Gap, width: CGFloat) -> some View {
        let text = content?.lines
        let shown = showsWholeFile ? [gap.first...gap.last] : expansion.shown(gap)
        // Above the lines where what is left is above them, or the row
        // sits between two lines that follow one another.
        if expansion.remainderIsAbove(gap) { expander(gap, width: width) }
        ForEach(shown, id: \.lowerBound) { range in
            ForEach(Array((text?.lines(from: range.lowerBound, through: range.upperBound) ?? [])
                .enumerated()), id: \.offset) { offset, source in
                let new = range.lowerBound + offset
                // The same text on both sides, because that is what an
                // unchanged line is. One blob fills two columns.
                HStack(alignment: .top, spacing: 0) {
                    contextCell(source, number: new + gap.oldOffset, width: width)
                    Divider().frame(width: Self.dividerWidth)
                    contextCell(source, number: new, width: width)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !expansion.remainderIsAbove(gap) { expander(gap, width: width) }
    }

    @ViewBuilder
    private func expander(_ gap: DiffGaps.Gap, width: CGFloat) -> some View {
        if let left = expansion.gap(gap), !showsWholeFile {
            ExpanderRow(
                gap: left,
                content: content,
                isLoading: isFetchingContent && expansion.isAwaiting(gap),
                open: { open(gap, $0) }
            )
            .frame(width: width * 2 + Self.dividerWidth, alignment: .leading)
        }
    }

    /// A press on a gap. Where the file is not here yet it is remembered
    /// and carried out when it arrives: the press means "show me", and
    /// whether that needed a request is not the reader's business.
    private func open(_ gap: DiffGaps.Gap, _ end: DiffGaps.Opening) {
        guard content?.lines != nil else {
            expansion.await(gap, end)
            fetchContent?()
            return
        }
        expansion.open(gap, end)
    }

    private func contextCell(
        _ source: String, number: Int, width: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if showsLineNumbers {
                Text(verbatim: "\(number)")
                    .font(.system(size: fontSize).monospaced())
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.gutterPadding + 14, alignment: .trailing)
                    .padding(.trailing, 6)
            }
            CodeText(
                source: source,
                language: language,
                insideComment: false,
                font: .system(size: fontSize).monospaced(),
                emphasis: [],
                emphasisTint: .clear
            )
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .padding(.vertical, 1)
    }

    private static let absent = Color(nsColor: .quaternaryLabelColor).opacity(0.18)
    private static let dividerWidth: CGFloat = 1
    private static let gutterPadding: CGFloat = 20
    /// Below this a column holds nothing worth reading, and the measurement
    /// is being taken before the layout has a width to give.
    private static let narrowest: CGFloat = 120

    private struct Row: Identifiable {
        enum Kind {
            case hunk(String)
            case note(String)
            case pair(DiffCell?, DiffCell?)
            case threads([ReviewThread])
            /// Lines the patch leaves out, and the row offering them.
            case gap(DiffGaps.Gap)
        }

        let id: Int
        let kind: Kind

        var isHunk: Bool { if case .hunk = kind { true } else { false } }
    }
}
