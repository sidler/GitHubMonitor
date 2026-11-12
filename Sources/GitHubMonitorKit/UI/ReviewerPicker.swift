import SwiftUI

/// Asks somebody else to look at this pull request.
///
/// Built the way the label picker is, and deliberately so: a filter field
/// over a list of the repository's people, GitHub doing the matching once
/// there is enough typed to match on. What differs is what a click costs.
/// A label tells nobody; a review request puts work in front of a
/// colleague and sends them a notification. So the click goes through at
/// once -- a question in front of every one of them would be ceremony --
/// and the pane keeps the way back for a few seconds afterwards.
struct ReviewerPicker: View {
    let editing: PaneWriting
    let item: PullRequestItem
    /// Who is already on the pull request, so the list does not offer
    /// them again.
    let asked: [ReviewerStatus]

    @StateObject private var open = ViewFlag()
    @StateObject private var typed = TypedText()

    /// Nothing is asked of GitHub until two letters: one letter matches
    /// most of a repository's people, and the request goes again on the
    /// next keystroke anyway.
    private var query: String {
        typed.text.count >= 2 ? typed.text : ""
    }

    private var listing: ReviewerListing {
        ReviewerListing(repository: item.repository, query: query)
    }

    private var answer: ReviewerCatalogueState? {
        editing.state.repositoryReviewers[listing]
    }

    var body: some View {
        Button { open.isOn.toggle() } label: {
            Label("Add", systemImage: "person.badge.plus")
                .font(.caption)
        }
        .buttonStyle(.accessoryBar)
        .help("Ask somebody else to review this")
        .popover(isPresented: $open.isOn, arrowEdge: .bottom) { picker }
        .onChange(of: open.isOn) {
            guard open.isOn else { return }
            editing.controller.loadReviewers(for: item.repository)
        }
        .onChange(of: query) {
            guard open.isOn else { return }
            editing.controller.loadReviewers(for: item.repository, matching: query)
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
        // A fixed box, for the reason the label picker has one: a popover
        // takes its size from whatever is in it the moment it opens and
        // never grows, so one opened on a spinner stayed the size of the
        // spinner and the people arriving behind it had nowhere to go.
        .frame(width: 300, height: 340)
    }

    private func list(_ catalogue: ReviewerQuery.Catalogue) -> some View {
        let offerable = ReviewerQuery.offerable(
            catalogue.candidates,
            // People only. A team carries its own name in the same
            // field, and a team named like somebody's login would
            // otherwise hide that person from the list.
            asked: Set(asked.filter { !$0.isTeam }.map { $0.name.lowercased() }),
            author: item.author,
            viewer: editing.state.viewer?.login
        )

        return VStack(alignment: .leading, spacing: 0) {
            if offerable.isEmpty {
                Text(
                    query.isEmpty
                        ? "Everybody here has been asked already."
                        : "Nobody of that name"
                )
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(10)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(offerable) { entry($0) }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            // Said rather than hidden, as the labels say it: a repository
            // of four hundred people would otherwise look like one of
            // fifty, and somebody would conclude a colleague had lost
            // their access.
            if !catalogue.isComplete {
                Divider()
                Text(
                    "Showing \(catalogue.candidates.count) of \(catalogue.total)"
                        + " \u{2014} type to narrow"
                )
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    private func entry(_ candidate: ReviewerCandidate) -> some View {
        Button {
            editing.controller.requestReview(from: candidate, on: item)
            open.isOn = false
        } label: {
            HStack(spacing: 7) {
                AvatarView(url: candidate.avatarURL, size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(candidate.login)
                        .font(.callout)
                    // The real name under the login. Twenty-seven logins
                    // is a list nobody can read; twenty-seven names is a
                    // team.
                    if let name = candidate.name {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
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

/// The way back from a review request just made.
///
/// Drawn where the reviewers are rather than at the foot of the pane, so
/// the offer sits beside the name it is about. It puts itself away after
/// a few seconds; a refusal does not, because a refusal is news and
/// somebody has to have seen it.
struct ReviewRequestUndoBar: View {
    let editing: PaneWriting
    let pullRequestID: String

    private var undo: ReviewRequestUndo? {
        guard let undo = editing.state.reviewRequestUndo,
            undo.pullRequestID == pullRequestID
        else { return nil }
        return undo
    }

    var body: some View {
        if let undo {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let failure = undo.failure {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Ink.orange)
                    Text(failure)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("OK") { editing.controller.dismissReviewRequestUndo() }
                        .buttonStyle(.accessoryBar)
                } else {
                    Text("Asked \(undo.login).")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if undo.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Undo") { editing.controller.undoReviewRequest() }
                            .buttonStyle(.accessoryBar)
                    }
                }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Color(nsColor: .quaternaryLabelColor).opacity(0.25),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
    }
}
