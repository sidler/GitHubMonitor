import Foundation

/// One line of a file drawn where the patch was silent, named by the
/// number it has in the file.
///
/// The name is the point. These rows used to be drawn as a list of
/// stretches, each holding a list numbered from nought -- so the first
/// row of every stretch of every gap was called "nought", and a lazy
/// stack that is told two rows are the same row is free to draw one of
/// them where the other belongs. It did: with the whole file shown, a
/// stretch of line 36 stood under the heading for line 1, and the place
/// line 36 should have been was blank.
///
/// A file line number is unique within a file, which is all the
/// identity a row here needs.
public struct ContextLine: Hashable, Sendable {
    /// The line's number in the file as it stands at the head commit,
    /// which is the version the blob holds.
    public let number: Int
    public let source: String

    public init(number: Int, source: String) {
        self.number = number
        self.source = source
    }

    /// The lines behind a gap's opened stretches, in file order.
    ///
    /// Flat, and in one pass: the view draws one list rather than a list
    /// of lists.
    public static func list(_ shown: [ClosedRange<Int>], from text: FileText?) -> [ContextLine] {
        shown
            .sorted { $0.lowerBound < $1.lowerBound }
            .flatMap { range in
                (text?.lines(from: range.lowerBound, through: range.upperBound) ?? [])
                    .enumerated()
                    .map { ContextLine(number: range.lowerBound + $0.offset, source: $0.element) }
            }
    }
}
