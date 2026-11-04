import AppKit
import SwiftUI

/// How a diff writes into the review being drafted. Nil leaves it a
/// reader, which is what it was until now.
struct DraftWriting {
    let add: (_ path: String, _ line: Int, _ side: ReviewThread.Side, _ body: String) -> Void
    let reply: (_ thread: ReviewThread, _ body: String) -> Void
    let change: (_ id: UUID, _ body: String) -> Void
    let remove: (_ id: UUID) -> Void
    let setResolved: (_ thread: ReviewThread, _ resolved: Bool) -> Void
    /// Who can be named with an `@` while writing. Nil leaves the editor
    /// a plain box, which is what it was.
    var mentioning: Mentioning?
}

/// Where the editor gets the names it offers.
///
/// Two closures rather than a reference to the app's state, because the
/// diff is handed what it may do and not what it may reach: the same
/// shape `DraftWriting` already has.
struct Mentioning {
    /// Called when what has been typed changes, and allowed to fetch.
    let ask: (_ query: String) -> Void
    /// Called while drawing, and not allowed to.
    let candidates: (_ query: String) -> [MentionableUser]
}

/// Where a remark is being written: a line of a file, or a conversation
/// being answered.
///
/// A value, so it can be the key a box is kept under and the question a
/// row asks when it draws itself.
struct DraftPlace: Hashable, Sendable {
    let path: String
    /// Nil where the box answers a conversation rather than a bare line.
    let line: Int?
    let side: ReviewThread.Side
    /// The conversation being answered, where it answers one.
    let replyTo: String?

    init(path: String, line: Int, side: ReviewThread.Side) {
        self.path = path
        self.line = line
        self.side = side
        replyTo = nil
    }

    init(reply thread: ReviewThread) {
        path = thread.path
        line = nil
        side = thread.side
        replyTo = thread.id
    }
}

/// One open box, and what has been typed in it.
@MainActor
final class DraftTarget: ObservableObject {
    let place: DraftPlace
    @Published var text: String
    /// The remark being reworded, where it is one that already exists.
    @Published var editing: UUID?
    /// Whether the markdown is being read rather than written.
    @Published var previewing = false

    init(place: DraftPlace, text: String = "", editing: UUID? = nil) {
        self.place = place
        self.text = text
        self.editing = editing
    }
}

/// Every box open in a review at once.
///
/// More than one, and that is the point. A review is read file by file,
/// and a thought about the third file does not wait politely for the
/// remark begun on the first to be finished. Each box is kept under the
/// place it was opened on, so turning the page leaves it where it was and
/// turning back finds it again, with what was typed still in it.
///
/// A box per place also keeps typing cheap: a keystroke publishes on that
/// one box, which the editor observes, and not on the thing the patch
/// view watches -- so a letter typed in a three-thousand-line file no
/// longer asks the whole file to draw itself again.
@MainActor
final class DraftBoxes: ObservableObject {
    @Published private(set) var boxes: [DraftPlace: DraftTarget] = [:]

    /// How many boxes are open.
    var count: Int { boxes.count }

    /// The boxes holding words, in the order they sit in the diff.
    ///
    /// An empty box is nothing anybody would miss, so it is not counted
    /// and not asked about. The order is settled rather than whatever
    /// the dictionary offers: these become remarks, and remarks that
    /// appear in a different order each time are remarks nobody trusts.
    var unfinished: [DraftTarget] {
        boxes.values
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                ($0.place.path, $0.place.line ?? .max, $0.place.side.rawValue)
                    < ($1.place.path, $1.place.line ?? .max, $1.place.side.rawValue)
            }
    }

    func box(at place: DraftPlace) -> DraftTarget? { boxes[place] }

    /// Whether a box is open on this line of this file. The file is part
    /// of the question: line 42 of one file is not line 42 of the next.
    func isOpen(path: String, line: Int, side: ReviewThread.Side) -> Bool {
        boxes[DraftPlace(path: path, line: line, side: side)] != nil
    }

    func isReplying(to threadID: String) -> Bool {
        boxes.keys.contains { $0.replyTo == threadID }
    }

    /// Opens a box, or hands back the one already there.
    ///
    /// Already there wins unless something is being put into it: pressing
    /// the plus twice on the same line should not wipe what was typed
    /// between the two presses.
    @discardableResult
    func open(
        path: String, line: Int, side: ReviewThread.Side,
        text: String = "", editing: UUID? = nil
    ) -> DraftTarget {
        open(DraftPlace(path: path, line: line, side: side), text: text, editing: editing)
    }

    @discardableResult
    func open(
        reply thread: ReviewThread, text: String = "", editing: UUID? = nil
    ) -> DraftTarget {
        open(DraftPlace(reply: thread), text: text, editing: editing)
    }

    @discardableResult
    private func open(
        _ place: DraftPlace, text: String, editing: UUID?
    ) -> DraftTarget {
        if let here = boxes[place], text.isEmpty, editing == nil { return here }
        let box = DraftTarget(place: place, text: text, editing: editing)
        boxes[place] = box
        return box
    }

    func shut(_ place: DraftPlace) {
        boxes[place] = nil
    }

    /// Empties every box, for a review whose words have been put
    /// somewhere they will keep -- or thrown away on purpose.
    func shutAll() {
        boxes = [:]
    }
}

/// Which row the pointer is over, so its number can offer itself.
///
/// A string rather than a row's number, because two columns have two
/// gutters and the pointer is in one of them.
@MainActor
final class HoveredRow: ObservableObject {
    @Published var key: String?

    func holds(_ key: String) -> Bool { self.key == key }

    func set(_ key: String, _ inside: Bool) {
        if inside {
            self.key = key
        } else if self.key == key {
            self.key = nil
        }
    }
}

/// A remark written but not sent.
///
/// Drawn like a conversation, because that is what it is about to become,
/// and in a colour of its own because it is the one thing in a diff that
/// nobody else can see yet.
struct DraftRemarkView: View {
    let comment: DraftComment
    let writing: DraftWriting
    let boxes: DraftBoxes

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Ink.purple)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.line")
                        .font(.caption2)
                    Text("Not sent yet")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)

                    Button("Edit") {
                        boxes.open(
                            path: comment.path,
                            line: comment.line,
                            side: comment.side,
                            text: comment.body,
                            editing: comment.id
                        )
                    }
                    Button("Delete") { writing.remove(comment.id) }
                }
                .font(.caption)
                .foregroundStyle(Ink.purple)
                .controlSize(.small)
                .buttonStyle(.accessoryBar)

                MarkdownText(source: comment.body, overflowNote: "")
                    .font(.callout)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.25))
        .padding(.vertical, 1)
    }
}

/// The box a remark is written in.
struct DraftEditorView: View {
    let path: String
    let line: Int
    let side: ReviewThread.Side
    /// The conversation being answered, where there is one. A reply
    /// names its thread and nothing else; the file and line go with it
    /// only so the draft can draw it in the right place.
    var thread: ReviewThread?
    let writing: DraftWriting
    /// The box this view is. Observed, so a keystroke redraws this and
    /// nothing else.
    @ObservedObject var box: DraftTarget
    /// Where it is kept, so it can be taken away again.
    let boxes: DraftBoxes

    @StateObject private var caret = CaretState()
    @StateObject private var pick = MentionPick()

    /// The half-typed name in front of the caret, if that is what is in
    /// front of the caret.
    private var query: String? {
        MentionTyping.query(
            in: box.text,
            before: MentionTyping.index(ofUTF16: caret.offset, in: box.text)
        )
    }

    /// Whom to offer. Nobody while the list has been dismissed for this
    /// very query -- escape should put it away and leave it away until
    /// what was typed changes.
    private var people: [MentionableUser] {
        guard
            let query, query != pick.dismissed,
            let mentioning = writing.mentioning
        else { return [] }
        return mentioning.candidates(query)
    }

    private var canSave: Bool {
        !box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Ink.purple)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                // Above the box, not below it: the word comes first in
                // the remark and first in the writing of one.
                ConventionalCommentBar(text: $box.text, caret: caret)

                MarkdownBar(text: $box.text, caret: caret, previewing: $box.previewing)

                if box.previewing {
                    preview
                } else {
                    editor
                }

                // Under the left edge of the box, where the writing
                // started and where the pointer already is. At the right
                // they were a trip across the whole diff -- and the
                // wider the window, the longer the trip.
                //
                // The one that sends comes first, nearest the text, with
                // Cancel behind it: that is the order of how often they
                // are pressed, not the order a sheet would put them in.
                HStack(spacing: 10) {
                    Button(label) { save() }
                        .disabled(!canSave)
                    Button("Cancel") { boxes.shut(box.place) }
                    Spacer(minLength: 8)
                    Text("Kept until you send the review")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.25))
        .padding(.vertical, 1)
        .onChange(of: query) {
            // A different question: the highlight goes back to the top,
            // and whatever was dismissed was dismissed about something
            // else.
            pick.index = 0
            pick.dismissed = nil
            guard let query else { return }
            writing.mentioning?.ask(query)
        }
    }

    /// What will be sent, read the way it will be read.
    private var preview: some View {
        ScrollView {
            MarkdownText(
                source: box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "*Nothing written yet.*"
                    : box.text,
                overflowNote: ""
            )
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 5)
        }
        .frame(minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    /// The box itself, with the list of names floating over it.
    private var editor: some View {
        CommentTextView(
            text: $box.text,
            caret: caret,
            fontSize: NSFont.preferredFont(forTextStyle: .callout).pointSize,
            focusesOnAppear: true,
            isCompleting: { !people.isEmpty },
            onMove: { pick.move($0, count: people.count) },
            onCommit: { take() },
            // One key, two meanings, innermost first: a list on screen is
            // what escape is about, and once it is gone the box is.
            onCancel: {
                if people.isEmpty {
                    boxes.shut(box.place)
                } else {
                    pick.dismissed = query
                }
            }
        )
        .frame(minHeight: 60)
        // A field, and it has to look like one. Drawn on the
        // conversation's own grey with a hairline round it, the box was
        // all but invisible -- you could not see where to start typing
        // without clicking to find out. Paper under it and a real border
        // round it.
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        // An overlay, not something in the stack: the list has to be able
        // to appear without the box changing height. That height is what
        // used to push the whole diff about as names were typed.
        .overlay(alignment: .topLeading) { completion }
        .zIndex(1)
    }

    /// The names on offer, floating under the caret.
    ///
    /// Under it vertically, which is the part that matters: in a card
    /// barely wider than the list there is no sideways room to follow a
    /// caret into, and a list that tried would hang off the edge and be
    /// cut in half. So it tracks the line being typed on and is held
    /// inside the box.
    @ViewBuilder
    private var completion: some View {
        if !people.isEmpty {
            GeometryReader { proxy in
                MentionList(people: people, selected: pick.index) { take($0) }
                    .offset(
                        x: min(
                            max(0, caret.rect.minX),
                            max(0, proxy.size.width - MentionList.width)
                        ),
                        y: caret.rect.maxY + 3
                    )
            }
        }
    }

    /// Takes the highlighted name. Answers whether there was one, so a
    /// return with no list under it is still a new paragraph.
    private func take() -> Bool {
        guard people.indices.contains(pick.index) else { return false }
        take(people[pick.index])
        return true
    }

    private func take(_ person: MentionableUser) {
        let written = MentionTyping.completing(
            box.text,
            with: person.login,
            before: MentionTyping.index(ofUTF16: caret.offset, in: box.text)
        )
        box.text = written.text
        // The caret belongs behind the name that was just written, not
        // wherever the new string happens to end.
        caret.wanted = NSRange(location: written.caret, length: 0)
        pick.index = 0
    }

    private var label: String {
        if box.editing != nil { return "Save" }
        return thread == nil ? "Add" : "Reply"
    }

    private func save() {
        guard canSave else { return }
        if let editing = box.editing {
            writing.change(editing, box.text)
        } else if let thread {
            writing.reply(thread, box.text)
        } else {
            writing.add(path, line, side, box.text)
        }
        boxes.shut(box.place)
    }
}

/// Which name in the list is highlighted, and whether the list has been
/// sent away.
@MainActor
final class MentionPick: ObservableObject {
    @Published var index = 0
    /// What was being typed when somebody pressed escape. The list stays
    /// away until that changes, rather than coming straight back on the
    /// next keystroke of the same word.
    @Published var dismissed: String?

    /// Up or down, round the ends: a list of four is quicker to reach
    /// from the bottom than by holding the up arrow.
    func move(_ by: Int, count: Int) {
        guard count > 0 else { return }
        index = ((index + by) % count + count) % count
    }
}

/// The names, floating at the caret.
struct MentionList: View {
    let people: [MentionableUser]
    let selected: Int
    let take: (MentionableUser) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                Button { take(person) } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: "@\(person.login)")
                            .font(.caption.weight(.medium))
                        if let name = person.name {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(
                                    index == selected ? .white.opacity(0.8) : .secondary
                                )
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(index == selected ? Color.white : Color(nsColor: .labelColor))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        index == selected ? Ink.blue : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }

            Divider().padding(.vertical, 3)

            HStack(spacing: 9) {
                key("\u{2191}\u{2193}", "choose")
                key("\u{21A9}", "insert")
                key("esc", "close")
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
        }
        .padding(4)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 7)
                // Opaque. The window's own background colour is not --
                // over a diff it let the code show through the names,
                // which made a list of logins unreadable exactly where
                // it mattered.
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    /// Wide enough for a login and most of a name beside it.
    static let width: CGFloat = 236

    private func key(_ symbol: String, _ what: String) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: symbol)
                .font(.system(size: 9))
                .padding(.horizontal, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(what).font(.system(size: 9.5))
        }
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
    }
}
