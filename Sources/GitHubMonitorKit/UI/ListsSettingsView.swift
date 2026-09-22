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
                // the same three switches, and their name and icon are as
                // much theirs as any list's. Only the search is not a thing
                // they have.
                mentionsRow.tag(ListVisibility.mentionsKey)
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
                    Text(settings.mentionsTitle)
                    Text("Unread notifications, filtered by reason in Filters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: settings.mentionsSymbol)
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
                Section("From a preset") {
                    ForEach(ListPresets.all) { preset in
                        Button {
                            add(preset.list())
                        } label: {
                            // The summary rather than the title alone: a
                            // preset is a search, and its name only hints at
                            // what it asks for.
                            Text(verbatim: "\(preset.title) — \(preset.summary)")
                        }
                    }
                }

                Section("Empty") {
                    ForEach(ListContent.allCases, id: \.self) { content in
                        Button(content.label) {
                            add(SavedList(
                                title: "New list",
                                query: content.queryPrefix,
                                content: content
                            ))
                        }
                    }
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
            // The mentions cannot be deleted, only switched off: there is
            // nothing to recreate them from.
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
        if model.selection == ListVisibility.mentionsKey {
            // The mentions borrow the list editor for the two fields they
            // do have. The rest is shown and disabled rather than hidden,
            // so it is clear that this entry is the same kind of thing with
            // less to set.
            ListEditor(
                list: SavedList(
                    id: ListVisibility.mentionsKey,
                    title: settings.mentionsTitle,
                    query: "Unread notifications from GitHub, not a search.",
                    content: .issues,
                    symbolName: settings.mentionsSymbol
                ),
                searchable: false,
                save: { list in
                    settings.mentionsTitle = list.title
                    settings.mentionsSymbol = list.symbol
                }
            )
        } else if let list = selected {
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

    private func add(_ list: SavedList) {
        settings.savedLists.append(list)
        model.selection = list.id
        // A preset arrives with a search that is ready to run, so there is
        // something to see without waiting for the next tick.
        Task { await controller.refresh() }
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
    /// False for the mentions, which have a name and an icon but no search
    /// and no choice of what they show.
    var searchable = true
    let save: (SavedList) -> Void

    @StateObject private var model: DraftModel

    init(list: SavedList, searchable: Bool = true, save: @escaping (SavedList) -> Void) {
        self.list = list
        self.searchable = searchable
        self.save = save
        _model = StateObject(wrappedValue: DraftModel(list))
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: binding(\.title))

                if searchable {
                    Picker("Shows", selection: binding(\.content)) {
                        ForEach(ListContent.allCases, id: \.self) { content in
                            Text(content.label).tag(content)
                        }
                    }
                } else {
                    // Not a disabled picker: the mentions show neither of
                    // the two things it offers, and a greyed-out "Issues"
                    // would be a wrong answer rather than an unavailable one.
                    LabeledContent("Shows", value: "Notifications")
                }

                LabeledContent("Icon") {
                    SymbolPicker(symbol: symbolBinding)
                }
            }

            Section("Search") {
                TextEditor(text: binding(\.query))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60)
                    .disabled(!searchable)
                    .foregroundStyle(
                        searchable
                            ? Color(nsColor: .labelColor)
                            : Color(nsColor: .secondaryLabelColor)
                    )

                if !searchable {
                    Text("""
                    Which notifications count is set by reason in the Filters \
                    tab, and how they are grouped by the control above the \
                    list itself.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if searchable {
                    Text("""
                    GitHub search syntax, one search per line; the results \
                    are merged. `@me` is you — and GitHub resolves your \
                    teams itself, so `review-requested:@me` already includes \
                    what is asked of a team you are on.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("""
                    The repository filter from Filters is added to a line \
                    that names no `repo:`, `org:` or `user:` of its own.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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

@MainActor
private final class SymbolPickerModel: ObservableObject {
    @Published var isOpen = false
    @Published var typed = ""
}

/// Picks the icon a list wears in the sidebar, the popover and the menu bar.
///
/// A grid of the ones that suit a list of work, and a field for any other SF
/// Symbol by name -- there are thousands, and which one means "release" to
/// somebody is not a thing to guess at. A name the system does not know is
/// refused rather than stored, since the icon would then be an empty gap in
/// three places at once.
private struct SymbolPicker: View {
    @Binding var symbol: String

    @StateObject private var model = SymbolPickerModel()

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8)

    var body: some View {
        Button {
            model.typed = symbol
            model.isOpen = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(symbol)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $model.isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(SavedList.symbolChoices, id: \.self) { choice in
                        Button {
                            symbol = choice
                            model.isOpen = false
                        } label: {
                            Image(systemName: choice)
                                .frame(width: 26, height: 22)
                                .background(
                                    choice == symbol
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(choice)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Any SF Symbol name", text: $model.typed)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .onSubmit { apply() }
                        Button("Use", action: apply)
                            .disabled(!isKnown(model.typed))
                    }
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(
                            isKnown(model.typed) || model.typed.isEmpty
                                ? Color(nsColor: .secondaryLabelColor)
                                : Color.orange
                        )
                }
            }
            .padding(12)
        }
    }

    private var hint: String {
        if model.typed.isEmpty {
            return "Names from the SF Symbols app, e.g. bolt.fill"
        }
        return isKnown(model.typed) ? "Looks good" : "No symbol of that name"
    }

    /// Asked of the system rather than matched against a list of our own:
    /// which symbols exist depends on the macOS the app is running on.
    private func isKnown(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private func apply() {
        guard isKnown(model.typed) else { return }
        symbol = model.typed
        model.isOpen = false
    }
}
