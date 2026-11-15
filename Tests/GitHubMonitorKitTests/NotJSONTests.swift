import Foundation
import Testing

@testable import GitHubMonitorKit

/// What the app says when GitHub answers successfully with something that
/// is not an answer.
///
/// The old message was "Unexpected response: response was not a JSON
/// object", which is true of an empty body, of a truncated one and of an
/// HTML page, and tells nobody which of the three they are looking at.
/// The status cannot be the fault -- a bad one has already been thrown by
/// then -- so what is worth saying is in the bytes.
@Suite("When GitHub answers with something that is not JSON")
struct NotJSONTests {
    @Test("An empty body is named as empty rather than as unparseable")
    func empty() {
        let said = GitHubClient.notJSON(Data(), status: 200)

        #expect(said.contains("200"))
        #expect(said.lowercased().contains("empty"))
    }

    /// The case that sent somebody looking: a 200 carrying a page.
    @Test("An HTML page is quoted far enough to be recognised")
    func html() {
        let page = Data(
            "<html><head><title>Unicorn!</title></head><body>Oops</body></html>".utf8
        )

        let said = GitHubClient.notJSON(page, status: 200)

        #expect(said.contains("200"))
        #expect(said.contains("\(page.count)"))
        #expect(said.contains("Unicorn"))
    }

    /// It lands in a status line somebody reads at a glance, so a
    /// megabyte of HTML must not be printed into it.
    @Test("A long body is cut short")
    func long() {
        let big = Data(String(repeating: "x", count: 5000).utf8)

        let said = GitHubClient.notJSON(big, status: 200)

        #expect(said.count < 300)
        #expect(said.contains("5000"))
    }

    /// Bytes that are not text at all still have a size worth reporting.
    @Test("Something that is not text is still described")
    func binary() {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        let said = GitHubClient.notJSON(bytes, status: 200)

        #expect(said.contains("6"))
        #expect(!said.isEmpty)
    }

    /// Whatever it says, it has to reach the reader through the error's
    /// own wording rather than being swallowed by it.
    @Test("The description carries the detail through")
    func throughTheError() {
        let said = GitHubClient.notJSON(Data(), status: 200)
        let error = GitHubError.decoding(said)

        #expect(error.errorDescription?.contains("empty") == true)
        #expect(error.errorDescription?.contains("200") == true)
    }
}
