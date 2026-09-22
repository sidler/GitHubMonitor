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
