import SwiftUI

/// How a diff writes into the review being drafted. Nil leaves it a
/// reader, which is what it was until now.
struct DraftWriting {
    let add: (_ path: String, _ line: Int, _ side: ReviewThread.Side, _ body: String) -> Void
    let reply: (_ thread: ReviewThread, _ body: String) -> Void
    let change: (_ id: UUID, _ body: String) -> Void
    let remove: (_ id: UUID) -> Void
    let setResolved: (_ thread: ReviewThread, _ resolved: Bool) -> Void
}

/// Which line is being written about, and what has been typed so far.
///
/// One of these for a whole file rather than one per row: only one remark
/// is written at a time, and a thousand objects for a thousand lines is a
/// thousand objects.
@MainActor
final class DraftTarget: ObservableObject {
    @Published var line: Int?
    @Published var side: ReviewThread.Side = .new
    @Published var text = ""
    /// The remark being reworded, where it is one that already exists.
    @Published var editing: UUID?
    /// The conversation being answered, where the box belongs to one
    /// rather than to a bare line.
    @Published var replyingTo: String?

    func open(line: Int, side: ReviewThread.Side, text: String = "", editing: UUID? = nil) {
        self.line = line
        self.side = side
        self.text = text
        self.editing = editing
        replyingTo = nil
    }

    func open(reply thread: ReviewThread, text: String = "", editing: UUID? = nil) {
        line = nil
        self.text = text
        self.editing = editing
        replyingTo = thread.id
    }

    func shut() {
        line = nil
        text = ""
        editing = nil
        replyingTo = nil
    }

    func isOpen(line: Int, side: ReviewThread.Side) -> Bool {
        replyingTo == nil && self.line == line && self.side == side
    }

    func isReplying(to threadID: String) -> Bool { replyingTo == threadID }
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
    @ObservedObject var target: DraftTarget

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
                        target.open(
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
                .buttonStyle(.accessoryBar)

                MarkdownText(source: comment.body, overflowNote: "")
                    .font(.callout)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.25))
        .padding(.vertical, 2)
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
    @ObservedObject var target: DraftTarget

    private var canSave: Bool {
        !target.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Ink.purple)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $target.text)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )

                HStack(spacing: 8) {
                    Text("Kept until you send the review")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Spacer(minLength: 8)
                    Button("Cancel") { target.shut() }
                    Button(label) { save() }
                        .disabled(!canSave)
                }
                .controlSize(.small)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.25))
        .padding(.vertical, 2)
    }

    private var label: String {
        if target.editing != nil { return "Save" }
        return thread == nil ? "Add" : "Reply"
    }

    private func save() {
        guard canSave else { return }
        if let editing = target.editing {
            writing.change(editing, target.text)
        } else if let thread {
            writing.reply(thread, target.text)
        } else {
            writing.add(path, line, side, target.text)
        }
        target.shut()
    }
}
