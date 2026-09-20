import Combine
import SwiftUI

@MainActor
private final class AccountFormModel: ObservableObject {
    @Published var token = ""
    @Published var isVerifying = false
    @Published var message: Message?

    enum Message: Equatable {
        case success(String)
        case failure(String)

        var text: String {
            switch self {
            case .success(let text), .failure(let text): text
            }
        }

        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }
    }
}

/// Token entry, scope verification and team selection.
struct AccountSettingsView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    @StateObject private var form = AccountFormModel()

    var body: some View {
        Form {
            if let viewer = state.viewer {
                signedInSection(viewer)
            } else {
                tokenEntrySection
            }

            teamsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Account

    private func signedInSection(_ viewer: Viewer) -> some View {
        Section("Account") {
            HStack(spacing: 10) {
                AvatarView(url: viewer.avatarURL, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewer.login).font(.headline)
                    Text(viewer.scopes.granted.sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign out", role: .destructive) {
                    controller.signOut()
                    form.token = ""
                    form.message = nil
                }
            }
        }
    }

    private var tokenEntrySection: some View {
        Section("Account") {
            SecureField("Personal access token", text: $form.token)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(form.isVerifying ? "Verifying…" : "Save and verify") {
                    Task { await verify() }
                }
                .disabled(form.token.isEmpty || form.isVerifying)

                Link("Create a token on GitHub", destination: Self.tokenCreationURL)
                    .font(.caption)
            }

            if let message = form.message {
                Label(message.text, systemImage: message.isFailure ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundStyle(message.isFailure ? .red : .green)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("A classic token is required; fine-grained tokens do not cover notifications.")
                ForEach(TokenScopes.required, id: \.scope) { entry in
                    Text("• \(entry.scope) — \(entry.purpose)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Pre-selects the scopes so the GitHub page opens ready to submit.
    static let tokenCreationURL = URL(
        string: "https://github.com/settings/tokens/new?description=GitHub%20Monitor&scopes=repo,notifications,read:org"
    )!

    private func verify() async {
        form.isVerifying = true
        form.message = nil
        defer { form.isVerifying = false }

        switch await controller.signIn(token: form.token) {
        case .success(let viewer):
            form.token = ""
            form.message = .success("Signed in as \(viewer.login)")
        case .failure(let error):
            form.message = .failure(error.localizedDescription)
        }
    }

    // MARK: - Teams

    private var teamsSection: some View {
        Section("Team review requests") {
            Text("Pull requests where one of these teams is the requested reviewer count as yours.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.availableTeams.isEmpty {
                HStack {
                    Button("Load my teams") {
                        Task { await loadTeams() }
                    }
                    .disabled(!state.hasToken)

                    if !state.settings.teamSlugs.isEmpty {
                        Text("\(state.settings.teamSlugs.count) configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(state.availableTeams) { team in
                    Toggle(isOn: binding(for: team)) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(team.name)
                            Text(team.slug).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }

    private func binding(for team: TeamMembership) -> Binding<Bool> {
        Binding(
            get: { state.settings.teamSlugs.contains(team.slug) },
            set: { isOn in
                var slugs = state.settings.teamSlugs
                if isOn {
                    guard !slugs.contains(team.slug) else { return }
                    slugs.append(team.slug)
                } else {
                    slugs.removeAll { $0 == team.slug }
                }
                state.settings.teamSlugs = slugs
                // The audience changed, so the counts are stale.
                Task { await controller.refresh() }
            }
        )
    }

    private func loadTeams() async {
        if let error = await controller.loadTeams() {
            form.message = .failure(error.localizedDescription)
        }
    }
}
