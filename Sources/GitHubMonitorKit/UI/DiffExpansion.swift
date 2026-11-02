import SwiftUI

/// Which stretches of a file have been opened, and how to open more.
///
/// View-local, like the open folders in the tree: it is about what one
/// reader is looking at, not about the pull request. One of these per
/// file on screen, keyed by the gap it belongs to.
@MainActor
final class Expansion: ObservableObject {
    /// What is left of each gap after what has been opened. A gap that is
    /// not in here has not been touched; a gap mapped to nil is gone.
    @Published private var remaining: [Int: DiffGaps.Gap?] = [:]
    /// The lines opened out of each gap, in file order.
    @Published private var opened: [Int: [ClosedRange<Int>]] = [:]

    /// What is still hidden at this gap, or nil once all of it is shown.
    func gap(_ gap: DiffGaps.Gap) -> DiffGaps.Gap? {
        guard let remembered = remaining[gap.id] else { return gap }
        return remembered
    }

    /// The stretches opened at this gap, oldest first.
    func shown(_ gap: DiffGaps.Gap) -> [ClosedRange<Int>] {
        (opened[gap.id] ?? []).sorted { $0.lowerBound < $1.lowerBound }
    }

    func open(_ gap: DiffGaps.Gap, _ end: DiffGaps.Opening) {
        guard let current = self.gap(gap) else { return }
        let (shown, left) = DiffGaps.remainder(of: current, opening: end)
        opened[gap.id, default: []].append(shown)
        remaining[gap.id] = left
    }
}

/// The row that stands where a patch is silent.
///
/// A line of its own rather than a gutter ornament: what it says -- how
/// much is missing, and that it can be had -- is the only thing on
/// screen that is about the code you cannot see.
struct ExpanderRow: View {
    let gap: DiffGaps.Gap
    /// Nil while the file has not been asked for yet.
    let content: FileContent?
    let isLoading: Bool
    let open: (DiffGaps.Opening) -> Void
    let fetch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let refusal = content?.refusal {
                Image(systemName: "exclamationmark.triangle")
                Text(refusal)
            } else if isLoading {
                ProgressView().controlSize(.mini)
                Text("Fetching the file…")
            } else {
                // Both ends offered only where it is worth the choice. On
                // a short gap one press takes the lot, and two chevrons
                // for a decision nobody has to make is two things to read.
                if gap.count > DiffGaps.openWholeUpTo {
                    button("chevron.up", "Show the \(DiffGaps.step) lines above") {
                        act { open(.bottom) }
                    }
                    button("chevron.down", "Show the \(DiffGaps.step) lines below") {
                        act { open(.top) }
                    }
                    Text("\(gap.count) lines hidden")
                    button("chevron.up.chevron.down", "Show all \(gap.count)") {
                        act { open(.whole) }
                    }
                } else {
                    button("chevron.up.chevron.down", "Show these \(gap.count) lines") {
                        act { open(.whole) }
                    }
                    Text(gap.count == 1 ? "1 line hidden" : "\(gap.count) lines hidden")
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        // The app talking, not the file -- the same light blue a settled
        // conversation's line uses, so the two read as one voice among
        // the code rather than as two.
        .foregroundStyle(Ink.cyan)
        .padding(.vertical, 3)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18))
    }

    /// Fetch first where it has not happened, then open. The press means
    /// "show me", and whether that needs a request is not the reader's
    /// business.
    private func act(_ opening: () -> Void) {
        guard content != nil else { return fetch() }
        opening()
    }

    private func button(
        _ symbol: String, _ help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption2)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(help)
    }
}

/// Which files are being read whole rather than hunk by hunk.
///
/// Per file, and only while the diff is open. Not a setting: "show me
/// all of this one" is a thing you mean about the file in front of you,
/// and a diff of forty-three files told to fetch all of them would be
/// forty-three requests nobody asked for.
@MainActor
final class WholeFiles: ObservableObject {
    @Published private var paths: Set<String> = []

    func holds(_ path: String) -> Bool { paths.contains(path) }

    func toggle(_ path: String) {
        if paths.contains(path) { paths.remove(path) } else { paths.insert(path) }
    }
}

/// How a diff gets at the unchanged lines around its hunks.
///
/// Three closures rather than a reference to the app's state, the same
/// shape `DraftWriting` already has: the diff is handed what it may do
/// and not what it may reach.
struct FileExpanding {
    /// What has been fetched for this blob, if anything has.
    let content: (String) -> FileContent?
    /// Whether a request for it is in the air.
    let isFetching: (String) -> Bool
    /// Go and get it. Called when somebody presses a gap for the first
    /// time, not when the diff opens.
    let fetch: (String) -> Void
}
