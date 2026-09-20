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
        #expect(scopes.missing == ["repo", "read:org"])
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
