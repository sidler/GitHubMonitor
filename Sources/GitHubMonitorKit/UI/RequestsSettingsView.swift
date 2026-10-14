import AppKit
import SwiftUI

/// Every request to GitHub and what came back.
///
/// Here because a run of 502s is otherwise invisible: the app says "the
/// request failed" and carries on, and the question somebody actually has
/// -- is it one call or all of them, is it constant or in bursts, what
/// does GitHub say when it refuses -- has nowhere to be answered from.
/// The successes matter as much as the failures: a log holding only the
/// failures cannot say whether anything was working in between.
///
/// Nothing is written to disk. This answers what is happening now, and a
/// file outliving that question would carry somebody's repository names
/// around for no one's benefit.
struct RequestsSettingsView: View {
    @Bindable var state: AppState

    @StateObject private var onlyTrouble = ViewFlag()

    private var shown: [RequestRecord] {
        let all = state.requests.newestFirst
        return onlyTrouble.isOn ? all.filter(\.outcome.isTrouble) : all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if state.requests.records.isEmpty {
                empty
            } else {
                List(shown) { record in
                    row(record)
                        .listRowSeparator(.visible)
                }
                .listStyle(.plain)
                .textSelection(.enabled)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Toggle("Only what went wrong", isOn: $onlyTrouble.isOn)
                .toggleStyle(.checkbox)

            Spacer(minLength: 8)

            Text(summary)
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.requests.transcript(), forType: .string)
            }
            .help("Copy the whole log as text, for pasting into a report")
            .disabled(state.requests.records.isEmpty)

            Button("Clear") { state.requests.clear() }
                .disabled(state.requests.records.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var summary: String {
        let count = state.requests.records.count
        let trouble = state.requests.troubles
        let kept = count == 1 ? "1 request" : "\(count) requests"
        guard trouble > 0 else { return "\(kept), none refused" }
        return "\(kept), \(trouble) refused"
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing asked for yet.")
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Text("The last \(state.requests.limit) requests appear here as they are made.")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func row(_ record: RequestRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(record.status)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint(record))
                    .frame(width: 30, alignment: .leading)

                Text(record.what)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                Text(String(format: "%.0f ms", record.duration * 1000))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                Text(RelativeTime.clock(record.startedAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .help(RelativeTime.absolute(record.startedAt))
            }

            // Only where there is something to say: on a good answer this
            // would be a blank line under every row.
            if let said = record.said {
                Text(said)
                    .font(.caption2)
                    .foregroundStyle(Ink.red)
                    .lineLimit(3)
                    .padding(.leading, 38)
            }
        }
        .padding(.vertical, 1)
    }

    /// Green for an answer, red for a refusal, grey for the ones that say
    /// nothing changed -- a 304 is a success worth telling apart, since a
    /// log full of them means the polling is doing its job for free.
    private func tint(_ record: RequestRecord) -> Color {
        switch record.outcome {
        case .failed: Ink.red
        case .answered(let status) where status >= 400: Ink.red
        case .answered(let status) where status == 304: Ink.gray
        case .answered: Ink.green
        }
    }
}
