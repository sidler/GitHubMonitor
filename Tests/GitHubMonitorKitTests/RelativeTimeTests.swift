import Foundation
import Testing
@testable import GitHubMonitorKit

@MainActor
@Suite("Relative time")
struct RelativeTimeTests {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A fresh timestamp reads as 'just now', not 'in 0 seconds'")
    func freshTimestamp() {
        #expect(RelativeTime.string(for: reference, relativeTo: reference) == "just now")
        #expect(RelativeTime.string(for: reference.addingTimeInterval(-30), relativeTo: reference) == "just now")
    }

    @Test("Older timestamps use relative wording")
    func olderTimestamp() {
        let text = RelativeTime.string(for: reference.addingTimeInterval(-7200), relativeTo: reference)
        #expect(text != "just now")
        #expect(text.contains("ago"))
    }

    /// The interface is English throughout, so timestamps must not follow the
    /// system locale -- on a German Mac that produced "vor 3 Tagen".
    @Test("Wording stays English regardless of system locale")
    func englishRegardlessOfLocale() {
        let text = RelativeTime.string(for: reference.addingTimeInterval(-86400 * 3), relativeTo: reference)
        #expect(text.contains("ago"))
        #expect(!text.contains("vor"))
    }
}
