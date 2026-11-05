import SwiftUI

/// Open pull requests per author, or reviews still owed per reviewer.
///
/// A table with a bar in it rather than a chart, which is what the two
/// reviewer rankings beside it are. Four views in one place that drew
/// themselves two different ways read as two different apps -- and the
/// table is the one that can carry its numbers in named columns instead
/// of making you hover for them.
struct WorkloadTableView: View {
    @Bindable var state: AppState
    let controller: RefreshController
    let data: DashboardData
    /// Whether this lists who is waiting for a review or who owes one.
    let byReviewer: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if byReviewer {
                        ForEach(Array(data.reviewers.enumerated()), id: \.element.id) { place, row in
                            WorkloadRow(
                                place: place + 1,
                                name: row.reviewer,
                                bar: row.pending,
                                most: mostOwed,
                                tint: Ink.orange,
                                numbers: [row.pending, row.onDrafts, row.done],
                                dimmed: dimmed(row.id),
                                help: "\(row.reviewer): \(row.pending) waiting"
                                    + ", \(row.onDrafts) on drafts, \(row.done) already given"
                            ) {
                                controller.toggleWorkload(
                                    WorkloadSelection(grouping: .reviewer, id: row.id)
                                )
                            }
                            Divider()
                        }
                    } else {
                        ForEach(Array(data.authors.enumerated()), id: \.element.id) { place, row in
                            WorkloadRow(
                                place: place + 1,
                                name: row.author,
                                bar: row.ready,
                                most: mostReady,
                                tint: Color.accentColor,
                                numbers: [row.ready, row.drafts, row.total],
                                dimmed: dimmed(row.id),
                                help: "\(row.author): \(row.ready) ready for review"
                                    + ", \(row.drafts) draft, \(row.total) open in total"
                            ) {
                                controller.toggleWorkload(
                                    WorkloadSelection(grouping: .author, id: row.id)
                                )
                            }
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
    }

    private var mostReady: Int { data.authors.map(\.ready).max() ?? 1 }
    private var mostOwed: Int { data.reviewers.map(\.pending).max() ?? 1 }

    /// While one row is being listed beside this, the others step back:
    /// the pane describes one of them, and nothing else should look
    /// equally current.
    private func dimmed(_ id: String) -> Bool {
        guard let selection = state.workloadSelection else { return false }
        return selection.id != id
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("#").frame(width: 24, alignment: .trailing)
            Text(byReviewer ? "reviewer" : "author")
                .frame(width: 180, alignment: .leading)
            Spacer(minLength: 0)
            ForEach(titles, id: \.self) { title in
                Text(title).frame(width: 72, alignment: .trailing)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private var titles: [String] {
        byReviewer ? ["waiting", "on drafts", "given"] : ["ready", "drafts", "open"]
    }

    /// What the columns mean, where the numbers end.
    ///
    /// The same bargain the reviewer rankings make: every one of these
    /// could be counted another way, and the reader should not have to
    /// guess which was chosen.
    private var footer: some View {
        HStack(spacing: 6) {
            Text(
                byReviewer
                    ? "waiting = reviews owed on pull requests that are ready"
                        + " \u{00B7} on drafts = owed on drafts, which block nobody yet"
                        + " \u{00B7} given = reviews already left \u{00B7} the bar is what is waiting"
                    : "ready = open and asking for review \u{00B7} drafts = not asking yet"
                        + " \u{00B7} open = both together \u{00B7} the bar is what is ready"
            )
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(count)
                .foregroundStyle(data.unread > 0 ? Ink.orange : .secondary)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
    }

    /// A chart adds its data up, so anything that could not be read is a
    /// bar too short rather than a row nobody scrolled to. Where that
    /// happens it has to be said, beside the numbers it affects.
    private var count: String {
        let counted = byReviewer
            ? "\(data.totalOutstandingReviews) reviews owed by \(data.reviewers.count) reviewers"
            : "\(data.total) open in \(data.repository)"
        guard data.unread > 0 else { return counted }
        return counted + " \u{00B7} \(data.unread) more not counted"
    }
}

/// One line of either table.
private struct WorkloadRow: View {
    let place: Int
    let name: String
    /// What the bar measures.
    let bar: Int
    let most: Int
    let tint: Color
    /// The columns after it, in the order their titles are written.
    let numbers: [Int]
    let dimmed: Bool
    let help: String
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                Text("\(place)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)

                Text(name)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)

                GeometryReader { proxy in
                    Capsule()
                        .fill(tint.opacity(0.7))
                        .frame(width: max(2, proxy.size.width * share), height: 10)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 18)

                ForEach(Array(numbers.enumerated()), id: \.offset) { index, number in
                    Text("\(number)")
                        .monospacedDigit()
                        .foregroundStyle(
                            index == 0 ? Color(nsColor: .labelColor) : .secondary
                        )
                        .frame(width: 72, alignment: .trailing)
                }
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(help + " \u{2014} click to list them")
        .accessibilityLabel(name)
        .accessibilityValue(help)
    }

    private var share: Double {
        guard most > 0 else { return 0 }
        return Double(bar) / Double(most)
    }
}
