import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("What Command-R reads again")
struct RefreshTargetTests {
    /// The three that were reported, and the reason the report was
    /// right: each of these pages carries its own reload button, and the
    /// key reached none of them.
    @Test("A chart page reads its own chart")
    func charts() {
        #expect(RefreshTarget.showing(.dashboard) == .workload)
        #expect(RefreshTarget.showing(.trends) == .trends)
        #expect(RefreshTarget.showing(.myTrends) == .myTrends)
    }

    @Test("Everywhere else reads the lists, as it always did")
    func lists() {
        #expect(RefreshTarget.showing(.list(id: "reviews", repository: nil)) == .lists)
        #expect(RefreshTarget.showing(.list(id: "x", repository: "octo/server")) == .lists)
        #expect(RefreshTarget.showing(.mentions(repository: nil)) == .lists)
        #expect(RefreshTarget.showing(.settings) == .lists)
    }

    /// A page added later must be thought about rather than falling
    /// through to the lists by accident. This is what makes the compiler
    /// ask: the switch over `SidebarSelection` is exhaustive, so a new
    /// case stops the build until somebody says what Command-R means on
    /// it. The test is here to say that out loud.
    @Test("Every page answers something")
    func total() {
        let pages: [SidebarSelection] = [
            .dashboard, .trends, .myTrends, .settings,
            .mentions(repository: nil), .list(id: "a", repository: nil),
        ]
        #expect(Set(pages.map(RefreshTarget.showing)).count == 4)
    }
}
