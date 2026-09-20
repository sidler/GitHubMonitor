import SwiftUI

/// Compact overview shown under the menu bar icon: the top few items of each
/// list plus a way into the full window.
struct PopoverView: View {
    @Bindable var state: AppState
    let openMainWindow: () -> Void
    let quit: () -> Void

    private static let previewLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if state.health == .unconfigured {
                unconfiguredNotice
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        section(
                            title: "Reviews requested",
                            count: state.pullRequests.count,
                            symbol: StatusBarTitleBuilder.pullRequestSymbol
                        ) {
                            ForEach(state.pullRequests.prefix(Self.previewLimit)) { item in
                                PullRequestRow(item: item, compact: true)
                            }
                        }

                        section(
                            title: "Unread mentions",
                            count: state.notifications.count,
                            symbol: StatusBarTitleBuilder.mentionSymbol
                        ) {
                            ForEach(state.notifications.prefix(Self.previewLimit)) { item in
                                NotificationRow(item: item, compact: true)
                            }
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            footer
        }
        .frame(width: 380, height: 460)
    }

    private var header: some View {
        HStack {
            Text("GitHub Monitor").font(.headline)
            Spacer()
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(state.health == .failing ? .red : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var unconfiguredNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: StatusBarTitleBuilder.unconfiguredSymbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No GitHub token configured")
                .font(.headline)
            Text("Add a personal access token to start monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") { openMainWindow() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        count: Int,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            .foregroundStyle(.secondary)

            if count == 0 {
                Text("Nothing here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                content()
                if count > Self.previewLimit {
                    Button("Show all \(count)…") { openMainWindow() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                // Wired up in stage 2.
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(state.loadState == .loading)

            Spacer()

            Button("Open Window") { openMainWindow() }
            Button("Quit") { quit() }
        }
        .buttonStyle(.accessoryBar)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
