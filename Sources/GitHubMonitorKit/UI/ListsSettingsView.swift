import Combine
import SwiftUI

/// View-local state without `@State`: its macro implementation ships only
/// with Xcode, and this project builds against the Command Line Tools.
@MainActor
private final class ListEditorModel: ObservableObject {
    @Published var selection: String?
    @Published var pendingDeletion: SavedList?
}

/// The lists in the sidebar: what they are called, what they search for, and
/// where each of them is shown.
struct ListsSettingsView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    @StateObject private var model = ListEditorModel()

    private var settings: Settings { state.settings }

    var body: some View {
        VStack(spacing: 0) {
            table
            Divider()
            editor
        }
        // Edits are written as they are made, but a search is only worth
        // running once the typing stops -- so the refresh waits for the tab
        // to be left rather than firing on every keystroke.
        .onDisappear { Task { await controller.refresh() } }
        .alert(item: $model.pendingDeletion) { list in
            Alert(
                title: Text("Delete “\(list.title)”?"),
                message: Text("The list and its query are removed. Nothing on GitHub changes."),
                primaryButton: .destructive(Text("Delete")) { delete(list) },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - The table

    private var table: some View {
        VStack(spacing: 0) {
            header
            List(selection: $model.selection) {
                ForEach(settings.savedLists) { list in
                    row(list).tag(list.id)
                }
                .onMove { indices, destination in
                    settings.savedLists.move(fromOffsets: indices, toOffset: destination)
                }

                // The mentions are not a saved list -- they come from the
                // notifications API rather than a search -- but they take
                // the same three switches, and hiding them in another tab
                // would be hiding them.
                mentionsRow
            }
            .listStyle(.inset)
            .frame(minHeight: 180)

            controls
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("List")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(DisplaySurface.allCases) { surface in
                Text(surface.label)
                    .frame(width: 76)
                    .help(surface.help)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func row(_ list: SavedList) -> some View {
        HStack(spacing: 0) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(list.title)
                    Text(summary(of: list))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: list.symbol)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(DisplaySurface.allCases) { surface in
                Toggle("", isOn: visibility(list.id, surface))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 76)
                    .help("\(list.title) — \(surface.help.lowercased())")
            }
        }
        .padding(.vertical, 2)
    }

    private var mentionsRow: some View {
        HStack(spacing: 0) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mentions")
                    Text("Unread notifications, filtered by reason in Filters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: StatusBarTitleBuilder.mentionSymbol)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(DisplaySurface.allCases) { surface in
                Toggle("", isOn: visibility(ListVisibility.mentionsKey, surface))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 76)
            }
        }
        .padding(.vertical, 2)
    }

    private func summary(of list: SavedList) -> String {
        let lines = list.queryLines
        guard let first = lines.first else { return "No query yet" }
        return lines.count == 1 ? first : "\(first)  +\(lines.count - 1) more"
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ListContent.allCases, id: \.self) { content in
                    Button(content.label) { add(content) }
                }
            } label: {
                Label("New list", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                if let list = selected { model.pendingDeletion = list }
            } label: {
                Label("Delete", systemImage: "minus")
            }
            .disabled(selected == nil)

            Spacer()

            Text("Drag to reorder. The sidebar, the popover and the menu bar all follow this order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.accessoryBar)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - The editor

    @ViewBuilder
    private var editor: some View {
        if let list = selected {
            ListEditor(
                list: list,
                save: { settings.update($0) }
            )
        } else {
            VStack(spacing: 6) {
                Text("Select a list to edit it")
                    .foregroundStyle(.secondary)
                Text("A list is a title and one or more GitHub searches.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var selected: SavedList? {
        guard let id = model.selection else { return nil }
        return settings.list(withID: id)
    }

    // MARK: - Editing

    private func visibility(_ key: String, _ surface: DisplaySurface) -> Binding<Bool> {
        Binding(
            get: { settings.listVisibility.isShown(key, in: surface) },
            set: { shown in
                var updated = settings.listVisibility
                updated.setShown(shown, key, in: surface)
                settings.listVisibility = updated
                state.normaliseSelection()
                // A list switched back on is not fetched until it is asked
                // for: the refresh only runs the lists that are shown.
                if shown { Task { await controller.refresh() } }
            }
        )
    }

    private func add(_ content: ListContent) {
        let list = SavedList(
            title: "New list",
            query: content.queryPrefix,
            content: content
        )
        settings.savedLists.append(list)
        model.selection = list.id
    }

    private func delete(_ list: SavedList) {
        settings.savedLists.removeAll { $0.id == list.id }
        var visibility = settings.listVisibility
        visibility.forget(list.id)
        settings.listVisibility = visibility
        state.listPullRequests[list.id] = nil
        state.listIssues[list.id] = nil
        model.selection = nil
        state.normaliseSelection()
    }
}

/// The fields of one list.
///
/// Bound to a copy and written back on every change rather than straight
/// through: the list lives in an array in settings, and editing it in place
/// would rewrite the whole stored document on every keystroke.
@MainActor
private final class DraftModel: ObservableObject {
    @Published var draft: SavedList

    init(_ list: SavedList) {
        draft = list
    }
}

private struct ListEditor: View {
    let list: SavedList
    let save: (SavedList) -> Void

    @StateObject private var model: DraftModel

    init(list: SavedList, save: @escaping (SavedList) -> Void) {
        self.list = list
        self.save = save
        _model = StateObject(wrappedValue: DraftModel(list))
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: binding(\.title))

                Picker("Shows", selection: binding(\.content)) {
                    ForEach(ListContent.allCases, id: \.self) { content in
                        Text(content.label).tag(content)
                    }
                }

                Picker("Icon", selection: symbolBinding) {
                    ForEach(SavedList.symbolChoices, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Search") {
                TextEditor(text: binding(\.query))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60)

                Text("""
                GitHub search syntax, one search per line; the results are \
                merged. `@me` is you. `@myteams` runs the line once per team \
                from the Account tab — which is how "requested from me or one \
                of my teams" is two searches rather than one.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("""
                The repository filter from Filters is added to a line that \
                names no `repo:`, `org:` or `user:` of its own.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // A different row was picked: start again from that list.
        .onChange(of: list.id) { model.draft = list }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SavedList, Value>) -> Binding<Value> {
        Binding(
            get: { model.draft[keyPath: keyPath] },
            set: { value in
                model.draft[keyPath: keyPath] = value
                save(model.draft)
            }
        )
    }

    private var symbolBinding: Binding<String> {
        Binding(
            get: { model.draft.symbol },
            set: { value in
                model.draft.symbolName = value
                save(model.draft)
            }
        )
    }
}
