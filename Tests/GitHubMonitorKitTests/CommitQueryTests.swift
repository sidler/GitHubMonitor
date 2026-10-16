import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("Reading a pull request's commits")
struct CommitQueryTests {
    private func payload(_ nodes: [[String: Any]]) -> [String: Any] {
        ["node": ["commits": ["totalCount": nodes.count, "nodes": nodes]]]
    }

    private func node(
        _ oid: String, headline: String, date: String = "2026-10-16T08:00:00Z",
        state: String? = nil, login: String? = "mira", name: String? = nil
    ) -> [String: Any] {
        var commit: [String: Any] = [
            "oid": oid,
            "abbreviatedOid": String(oid.prefix(7)),
            "messageHeadline": headline,
            "committedDate": date,
            "commitUrl": "https://github.com/octo/server/commit/\(oid)",
        ]
        var author: [String: Any] = [:]
        if let login { author["user"] = ["login": login, "avatarUrl": "https://a/\(login)"] }
        if let name { author["name"] = name }
        commit["author"] = author
        if let state { commit["statusCheckRollup"] = ["state": state] }
        return ["commit": commit]
    }

    /// GitHub hands them over oldest first. The pane is read by somebody
    /// coming back to a pull request, whose question is what arrived
    /// since -- and every other list in this app is newest first.
    @Test("They come back newest first")
    func newestFirst() throws {
        let commits = try CommitQuery.commits(from: payload([
            node("aaa1111", headline: "first"),
            node("bbb2222", headline: "second"),
            node("ccc3333", headline: "third"),
        ]))
        #expect(commits.map(\.headline) == ["third", "second", "first"])
    }

    @Test("Each one carries what a row shows")
    func fields() throws {
        let commits = try CommitQuery.commits(from: payload([
            node("a3f91c20b1d2", headline: "Take the lock first", state: "SUCCESS")
        ]))
        let commit = try #require(commits.first)
        #expect(commit.abbreviated == "a3f91c2")
        #expect(commit.headline == "Take the lock first")
        #expect(commit.author == "mira")
        #expect(commit.avatarURL != nil)
        #expect(commit.checks == .success)
        #expect(commit.url?.absoluteString.hasSuffix("a3f91c20b1d2") == true)
    }

    /// A commit by somebody without a GitHub account is still a commit by
    /// somebody.
    @Test("Without an account, the name written into the commit is used")
    func noAccount() throws {
        let commits = try CommitQuery.commits(from: payload([
            node("ddd4444", headline: "x", login: nil, name: "Jane Hacker")
        ]))
        #expect(commits.first?.author == "Jane Hacker")
        #expect(commits.first?.avatarURL == nil)
    }

    @Test("The rollup's word becomes the mark on the row")
    func states() {
        func status(_ state: String?) -> ChecksStatus {
            var commit: [String: Any] = [:]
            if let state { commit["statusCheckRollup"] = ["state": state] }
            return CommitQuery.status(of: commit)
        }
        #expect(status("SUCCESS") == .success)
        #expect(status("FAILURE") == .failure)
        #expect(status("ERROR") == .failure)
        #expect(status("PENDING") == .pending)
        #expect(status("EXPECTED") == .pending)
        // No checks at all is not a failure, and must not be drawn as one.
        #expect(status(nil) == .none)
        #expect(status("SOMETHING_NEW") == .none)
    }

    @Test("An abbreviation GitHub did not give falls back to seven characters")
    func abbreviation() {
        let commit = PullRequestCommit(oid: "0123456789abcdef", headline: "x")
        #expect(commit.abbreviated == "0123456")
    }

    @Test("Something that is not a pull request is an error, not an empty list")
    func refusesNonsense() {
        #expect(throws: GitHubError.self) {
            _ = try CommitQuery.commits(from: ["node": NSNull()])
        }
    }

    @Test("A node without an oid is not a commit")
    func skipsNonsense() throws {
        let commits = try CommitQuery.commits(from: payload([
            ["commit": ["messageHeadline": "no oid"]],
            node("eee5555", headline: "real"),
        ]))
        #expect(commits.map(\.headline) == ["real"])
    }

    /// The newest fifty rather than the fifty it started with: what goes
    /// missing from a long pull request is then the half nobody scrolls to.
    @Test("The query asks for the last page, not the first")
    func asksForTheNewest() {
        #expect(CommitQuery.document.contains("commits(last: \(CommitQuery.pageSize))"))
        #expect(CommitQuery.pageSize == 50)
    }
}
