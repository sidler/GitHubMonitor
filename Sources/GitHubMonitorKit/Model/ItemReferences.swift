import Foundation

/// Finds issue and pull request numbers written in ordinary text.
///
/// GitHub records a link only for the "closes #123" form. Everything else a
/// person writes -- the number at the head of a title, the number in a
/// sentence -- is text, and this is what reads it.
public enum ItemReferences {
    /// How many are taken from one piece of text. A body that names more
    /// numbers than this is a changelog, and the browser is where those are
    /// read.
    public static let limit = 5

    /// The number a title opens with is this project's way of saying which
    /// issue the work belongs to, so it counts as a link. Any other number
    /// in the title is part of a sentence.
    public static func inTitle(_ title: String, repository: String) -> [ItemLink] {
        found(in: title, repository: repository).map { match in
            ItemLink(
                reference: match.reference,
                kind: match.start == title.startIndex ? .closes : .mentions
            )
        }
    }

    /// Every number in the body, as mentions.
    ///
    /// Code and quotes are left out: a number in a log extract or in
    /// somebody else's quoted comment is not this item saying anything.
    public static func inBody(_ body: String, repository: String) -> [ItemLink] {
        let prose = MarkdownDocument.blocks(from: body).flatMap(text(of:))
        return prose
            .flatMap { found(in: $0, repository: repository) }
            .map { ItemLink(reference: $0.reference, kind: .mentions) }
    }

    /// What of a block is somebody writing prose.
    static func text(of block: MarkdownBlock) -> [String] {
        switch block {
        case .paragraph(let text): [text]
        case .heading(_, let text): [text]
        case .bullets(let items): items.map(\.text)
        case .numbered(let items): items
        case .table(let header, let rows): header + rows.flatMap { $0 }
        // A number in a code fence is code, and a number in a quote was
        // written by someone else somewhere else.
        case .code, .quote, .rule: []
        }
    }

    // MARK: - Reading

    struct Match {
        let reference: ItemReference
        let start: String.Index
    }

    /// `#123`, or `owner/name#123` where the number belongs to another
    /// repository.
    ///
    /// The lookbehind is the whole trick: without it every anchor in a URL
    /// (`\u{2026}/pull/12#issuecomment-1`) and every version like `v2#3`
    /// would read as a reference. A number may follow the start of the
    /// text, a space, or an opening piece of punctuation, and nothing else.
    private static let pattern = try? NSRegularExpression(
        pattern: #"(?<![\w/.\-])(?:([A-Za-z0-9._-]+/[A-Za-z0-9._-]+))?#(\d+)\b"#
    )

    static func found(in text: String, repository: String) -> [Match] {
        guard let pattern else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        var result: [Match] = []
        var seen = Set<ItemReference>()

        for match in pattern.matches(in: text, range: range) {
            guard
                let whole = Range(match.range, in: text),
                let numberRange = Range(match.range(at: 2), in: text),
                let number = Int(text[numberRange]),
                number > 0
            else { continue }

            let owner = Range(match.range(at: 1), in: text).map { String(text[$0]) }
            let reference = ItemReference(repository: owner ?? repository, number: number)
            guard seen.insert(reference).inserted else { continue }

            result.append(Match(reference: reference, start: whole.lowerBound))
            if result.count == limit { break }
        }

        return result
    }
}
