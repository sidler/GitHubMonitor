import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Token scopes")
struct TokenScopesTests {
    @Test("Header is split and trimmed")
    func parsing() {
        let scopes = TokenScopes(header: "repo, notifications,read:org")
        #expect(scopes.granted == ["repo", "notifications", "read:org"])
    }

    @Test("A missing header means no scopes")
    func missingHeader() {
        #expect(TokenScopes(header: nil).granted.isEmpty)
        #expect(TokenScopes(header: "").granted.isEmpty)
    }

    @Test("A complete token reports nothing missing")
    func complete() {
        let scopes = TokenScopes(header: "repo, notifications, read:org")
        #expect(scopes.isComplete)
        #expect(scopes.missing.isEmpty)
    }

    @Test("Missing scopes are listed in the documented order")
    func missingScopes() {
        let scopes = TokenScopes(header: "notifications")
        #expect(scopes.missing == ["repo"])
    }

    /// `read:org` was only ever needed to list the user's teams, and the
    /// app stopped doing that when it turned out GitHub resolves team
    /// membership inside `review-requested:` itself. A token without it is
    /// complete now, and one with it is not asked to give it up.
    @Test("read:org is no longer required, nor in the way")
    func organisationScopeIsOptional() {
        #expect(!TokenScopes.required.map(\.scope).contains("read:org"))
        #expect(TokenScopes(header: "repo, notifications").isComplete)
        #expect(TokenScopes(header: "repo, notifications, read:org").isComplete)
    }

    /// GitHub lists only the broadest scope granted, so a token with
    /// `admin:org` must not be reported as missing `read:org`.
    @Test("Broader scopes satisfy narrower requirements")
    func implications() {
        let scopes = TokenScopes(header: "repo, notifications, admin:org")
        #expect(scopes.has("read:org"))
        #expect(scopes.isComplete)
    }

    @Test("A narrower scope does not satisfy a broader requirement")
    func implicationsDoNotRunBackwards() {
        let scopes = TokenScopes(header: "public_repo, notifications, read:org")
        #expect(!scopes.has("repo"))
        #expect(scopes.missing == ["repo"])
    }
}

/// The settings screen promises what the token will be used for, and the
/// promise has to match the code. It once said the app wrote "exactly one
/// thing" for several releases after it had learnt to merge, to label and
/// to resolve.
@Suite("What the token is said to be for")
struct TokenPurposeTests {
    private var repoPurpose: String {
        TokenScopes.required.first { $0.scope == "repo" }?.purpose ?? ""
    }

    /// One line per kind of write the app performs. Adding a mutation
    /// without naming it here should fail, which is the point.
    @Test("Every kind of write the app does is named")
    func namesEveryWrite() {
        for write in ["remarks", "review", "resolving", "labels", "viewed", "merging"] {
            #expect(
                repoPurpose.localizedCaseInsensitiveContains(write),
                "the repo scope does not say it writes \(write)"
            )
        }
    }

    /// The scope grants write across every repository the account can
    /// reach, and saying otherwise would be the one misstatement that
    /// matters here.
    @Test("The scope is described as the full access it is")
    func saysItIsFullAccess() {
        #expect(repoPurpose.localizedCaseInsensitiveContains("full access"))
        #expect(repoPurpose.localizedCaseInsensitiveContains("private"))
        #expect(!repoPurpose.localizedCaseInsensitiveContains("exactly one"))
    }

    @Test("Notifications say both halves of what they are for")
    func notifications() {
        let purpose = TokenScopes.required.first { $0.scope == "notifications" }?.purpose
        #expect(purpose?.contains("read") == true)
        #expect(purpose?.contains("mark them read") == true)
    }
}
