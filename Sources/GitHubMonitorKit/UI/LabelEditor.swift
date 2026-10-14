import SwiftUI

/// What a pane needs to change an item's labels. Nil leaves them as
/// something to read.
struct LabelEditing {
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
    let editing: LabelEditing
    let repository: String
    let itemID: String
    let isPullRequest: Bool
    /// What the item carries now, so the list can tick them and put them
    /// at the top.
    let current: [IssueLabel]
    /// The chips as the pane draws them. Inside the button rather than
    /// beside it: a row of labels is what somebody aims at when they
    /// want to change the labels, and a tag eleven points wide is a
    /// target you have to find first.
    @ViewBuilder var row: () -> Row

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
        Button {
            open.isOn.toggle()
        } label: {
            row().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Add or remove labels")
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
                        ForEach(LabelQuery.ordered(catalogue.labels, carrying: current)) {
                            entry($0)
                        }
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
