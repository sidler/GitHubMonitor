import SwiftUI

/// What a pane needs to change anything: the state to read and the
/// controller to ask. Nil leaves the pane a reader.
///
/// One of these rather than one per thing that can be written. Labels and
/// merging both need exactly this, and a second struct with the same two
/// fields would be two names for one idea.
struct PaneWriting {
    let state: AppState
    let controller: RefreshController
}

/// View-local text without `@State`, whose macro ships only with Xcode.
@MainActor
final class TypedText: ObservableObject {
    @Published var text = ""
}

/// Puts a label on an item and takes it off again.
///
/// The one thing this app writes without asking first. An approval is
/// public and cannot be taken back; a merge puts code in a branch. A
/// label tells nobody, changes nothing that runs, and is undone by the
/// same click that set it -- a confirmation in front of that would be
/// ceremony for its own sake.
///
/// What it owes instead is honesty about what has actually happened. The
/// change is shown at once, because waiting a round trip to see a tick
/// appear is what makes a picker feel broken; if GitHub refuses, the
/// label goes back where it was, and the Requests tab has the refusal.
struct LabelEditor<Row: View>: View {
    let editing: PaneWriting
    let repository: String
    let itemID: String
    let isPullRequest: Bool
    /// What the item carries now, so the list can tick them and put them
    /// at the top.
    let current: [IssueLabel]
    /// The chips as the pane draws them, handed what opens the picker.
    ///
    /// The row is not wrapped in one button any more. It used to be, so
    /// that the whole line was the target rather than a tag eleven
    /// points wide -- but the same line also carries things that are
    /// not labels and that this cannot set: an issue's type, its
    /// milestone. Those read as labels and then did not behave as any:
    /// clicking "Epic" opened a picker that neither held it nor could.
    ///
    /// So each caller says which of its chips opens the picker. They
    /// stay in one `FlowRow`, which is what keeps the type, the labels
    /// and the tag wrapping together as one line of chips.
    @ViewBuilder var row: (@escaping () -> Void) -> Row

    @StateObject private var open = ViewFlag()
    @StateObject private var typed = TypedText()

    /// What is asked of GitHub: nothing until two characters, because one
    /// letter matches most of a repository's taxonomy and the request is
    /// made again on the next keystroke anyway.
    private var query: String {
        typed.text.count >= 2 ? typed.text : ""
    }

    private var answer: LabelCatalogueState? {
        editing.state.repositoryLabels[LabelRequest(repository: repository, query: query)]
    }

    var body: some View {
        row { open.isOn.toggle() }
            .popover(isPresented: $open.isOn, arrowEdge: .bottom) { picker }
            .onChange(of: open.isOn) {
                guard open.isOn else { return }
                editing.controller.loadLabels(for: repository)
            }
            .onChange(of: query) {
                guard open.isOn else { return }
                editing.controller.loadLabels(for: repository, matching: query)
            }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Filter", text: $typed.text)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            Group {
                switch answer {
                case .loaded(let catalogue):
                    list(catalogue)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Ink.red)
                        .padding(10)
                case .loading, nil:
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // One size whatever is in it. A popover measures itself against
        // its content as it opens and does not grow afterwards, so one
        // opened while the labels were still on their way kept the size
        // of the spinner -- which was a box with nothing in it and no way
        // to tell that sixty labels had since arrived. A fixed box also
        // gives the list below a height to scroll within; left to itself
        // inside a popover nothing proposes it one, and it takes the
        // smallest it can.
        .frame(width: 300, height: 340)
    }

    private func list(_ catalogue: LabelQuery.Catalogue) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if catalogue.labels.isEmpty {
                Text("No label of that name")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(10)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let shown = LabelQuery.ordered(
                            catalogue.labels, carrying: current, narrowed: !query.isEmpty
                        )
                        ForEach(shown) { entry($0) }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            // Said rather than hidden: a repository with four hundred
            // labels would otherwise look like one with sixty, and
            // somebody would conclude theirs had been deleted.
            if !catalogue.isComplete {
                Divider()
                Text("Showing \(catalogue.labels.count) of \(catalogue.total) \u{2014} type to narrow")
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
    }

    private func entry(_ label: IssueLabel) -> some View {
        let isOn = current.contains { $0.id == label.id }
        return Button {
            editing.controller.setLabel(
                label, on: itemID, isPullRequest: isPullRequest, to: !isOn
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(
                        isOn ? Ink.blue : Color(nsColor: .tertiaryLabelColor)
                    )
                LabelChip(label: label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}


/// The mark at the end of a row of labels that says the row can be
/// pressed.
///
/// A hint rather than the target: the whole row is the button, and this
/// is there so somebody knows that before they try.
struct LabelTag: View {
    var body: some View {
        Image(systemName: "tag")
            .font(.caption)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
    }
}

/// A chip that opens the label picker.
///
/// Every label is one, and so is the tag at the end of the row: what
/// somebody aims at when they want to change the labels is a label, not
/// an icon eleven points wide. What is not one of these is a chip that
/// is not a label -- and it stays quiet rather than opening a picker it
/// has nothing to do with.
struct LabelOpener<Content: View>: View {
    let open: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: open) {
            content().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Add or remove labels")
    }
}
