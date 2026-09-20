import Combine
import SwiftUI

@MainActor
private final class FilterEntryModel: ObservableObject {
    @Published var draft = ""
}

/// Restricts what counts, by owner or by repository.
struct RepositoryFilterView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    @StateObject private var entry = FilterEntryModel()

    private var filters: [String] { state.settings.repositoryFilters }

    /// Names seen in the current results that are not filtered already --
    /// typing an exact repository name from memory is error-prone, so offer
    /// what is actually there.
    private var suggestions: [String] {
        let repositories = RepositoryGrouping.repositories(
            pullRequests: state.pullRequests,
            notifications: state.notifications
        )
        let owners = RepositoryGrouping.owners(of: repositories)
        return (owners + repositories).filter { !filters.contains($0) }
    }

    var body: some View {
        Section("Repositories") {
            Text("Only count pull requests and mentions in these owners or repositories. With none listed, everything counts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(filters, id: \.self) { filter in
                HStack {
                    Image(systemName: filter.contains("/") ? "book.closed" : "building.2")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(filter)
                    Spacer()
                    Button {
                        remove(filter)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove this filter")
                }
            }

            HStack {
                TextField("owner or owner/repository", text: $entry.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add(entry.draft) }
                Button("Add") { add(entry.draft) }
                    .disabled(!isValid(entry.draft))
            }

            if !suggestions.isEmpty {
                Menu("Add from current results") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { add(suggestion) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Editing

    private func isValid(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.hasSuffix("/") else { return false }
        // At most one slash: "owner" or "owner/repository".
        guard trimmed.filter({ $0 == "/" }).count <= 1 else { return false }
        return !filters.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func add(_ candidate: String) {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard isValid(trimmed) else { return }
        state.settings.repositoryFilters = filters + [trimmed]
        entry.draft = ""
        refresh()
    }

    private func remove(_ filter: String) {
        state.settings.repositoryFilters = filters.filter { $0 != filter }
        refresh()
    }

    /// The filter also narrows the GitHub query, so the results are stale
    /// until refetched -- local filtering alone would hide items that a
    /// widened filter should bring back.
    private func refresh() {
        Task { await controller.refresh() }
    }
}
