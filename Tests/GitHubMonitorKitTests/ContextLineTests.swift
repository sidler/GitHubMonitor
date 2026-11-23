import Foundation
import Testing

@testable import GitHubMonitorKit

/// The rows drawn where a patch is silent, and the names they are drawn
/// under.
///
/// The name is the whole point. These used to be a list of stretches,
/// each holding a list numbered from nought, so the first row of every
/// stretch of every gap was called "nought" -- and a lazy stack that is
/// told two rows are the same row is free to draw one where the other
/// belongs. With the whole file shown it did: a stretch of line 36 stood
/// under the heading for line 1, and line 36's own place was blank.
@Suite("Lines filled in behind a patch")
struct ContextLineTests {
    private var file: FileText {
        FileText((1...60).map { "line \($0)" }.joined(separator: "\n"))
    }

    @Test("Each line is named by its own number in the file")
    func namedByFileLine() {
        let drawn = ContextLine.list([5...7], from: file)

        #expect(drawn.map(\.number) == [5, 6, 7])
        #expect(drawn.first?.source == "line 5")
    }

    /// Two stretches of one gap, and two gaps on one file: no two rows
    /// anywhere may answer to the same name.
    @Test("No two rows share a name")
    func namesAreUnique() {
        let first = ContextLine.list([1...7], from: file)
        let second = ContextLine.list([36...39], from: file)
        let split = ContextLine.list([15...17, 24...26], from: file)

        let all = first + second + split
        #expect(Set(all.map(\.number)).count == all.count)
        // The names are the file's own numbers, so they say where a row
        // belongs as well as which row it is.
        #expect(second.map(\.number) == [36, 37, 38, 39])
        #expect(split.map(\.number) == [15, 16, 17, 24, 25, 26])
    }

    /// Opened from the bottom and then from the top, the stretches are
    /// remembered in the order they were pressed. They are drawn in the
    /// order they run down the file.
    @Test("Stretches are drawn in file order, whatever order they were opened in")
    func fileOrder() {
        let drawn = ContextLine.list([20...22, 5...7], from: file)
        #expect(drawn.map(\.number) == [5, 6, 7, 20, 21, 22])
    }

    /// A gap can name lines past the end of the blob: a file moves on,
    /// and the honest answer is the lines that exist.
    @Test("A stretch past the end of the file yields what is there")
    func pastTheEnd() {
        #expect(ContextLine.list([58...70], from: file).map(\.number) == [58, 59, 60])
        #expect(ContextLine.list([5...7], from: nil).isEmpty)
    }
}
