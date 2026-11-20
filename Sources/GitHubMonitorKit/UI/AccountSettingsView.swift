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

/// Token entry and scope verification.
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

            scopeSection
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
                    .foregroundStyle(message.isFailure ? Ink.red : Ink.green)
                    .font(.caption)
            }

            Text("A classic token is required; fine-grained tokens do not cover notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// What each scope buys, and whether this token carries it.
    ///
    /// Shown signed in as well as signed out. Signed out it is a shopping
    /// list; signed in it is the answer to "why will the app not do that",
    /// which until now was a comma-separated line of scope names that said
    /// what the token had and never what any of it was for.
    private var scopeSection: some View {
        Section("What the token may do") {
            ForEach(TokenScopes.catalogue, id: \.scope) { entry in
                scopeRow(entry)
            }

            if state.viewer != nil, !missingOptional.isEmpty {
                Text(
                    "A scope added to a token afterwards needs a new token here: "
                        + "GitHub does not change the one you pasted."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Nil while there is no token: nothing has been granted or refused
    /// yet, and a column of crosses would read as a fault rather than as
    /// a list of what to tick on GitHub.
    private var granted: TokenScopes? { state.viewer?.scopes }

    private var missingOptional: [String] {
        TokenScopes.optional.map(\.scope).filter { granted?.has($0) == false }
    }

    private func scopeRow(
        _ entry: (scope: String, purpose: String, isRequired: Bool)
    ) -> some View {
        let has = granted?.has(entry.scope)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol(has, required: entry.isRequired))
                .foregroundStyle(tint(has, required: entry.isRequired))
                .font(.caption)
                // Fixed width, or the sentences beside them start at
                // three different places down the column.
                .frame(width: 13, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.scope)
                        .font(.system(.caption, design: .monospaced))
                    if !entry.isRequired {
                        Text("optional")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func symbol(_ has: Bool?, required: Bool) -> String {
        guard let has else { return "circle" }
        if has { return "checkmark.circle.fill" }
        return required ? "xmark.octagon.fill" : "circle.dashed"
    }

    private func tint(_ has: Bool?, required: Bool) -> AnyShapeStyle {
        guard let has else { return AnyShapeStyle(.tertiary) }
        if has { return AnyShapeStyle(Ink.green) }
        // Missing and optional is not a fault: the app works, it just
        // does less. Only a missing required scope is red.
        return required ? AnyShapeStyle(Ink.red) : AnyShapeStyle(.secondary)
    }

    /// Pre-selects the scopes so the GitHub page opens ready to submit.
    static let tokenCreationURL = URL(
        string: "https://github.com/settings/tokens/new?description=GitHub%20Monitor"
            + "&scopes=repo,notifications,project,read:org"
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
}
