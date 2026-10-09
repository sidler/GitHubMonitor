import Foundation

/// One issue or pull request, named by repository and number.
///
/// Number and repository rather than a node id: a number read out of a
/// title or a sentence is all there is to go on, and it is enough to ask
/// GitHub for the rest.
public struct ItemReference: Hashable, Sendable, Identifiable {
    /// "owner/name"
    public let repository: String
    public let number: Int

    public var id: String { "\(repository)#\(number)" }

    public init(repository: String, number: Int) {
        self.repository = repository
        self.number = number
    }
}

/// A link from one item to another, and how much the link is worth.
///
/// Two kinds, because two very different things look the same in a body.
/// `closes` is what GitHub itself records, plus the number this project
/// writes at the head of a title; `mentions` is a number in a sentence,
/// which may be the issue this work belongs to or may be "as discussed in
/// #4711". Showing them in one list would put the question and an aside
/// side by side as equals.
public struct ItemLink: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case closes
        case mentions

        /// Which of two answers about the same item to keep.
        ///
        /// Written out rather than left to `Comparable` on the declaration
        /// order: reordering the cases would otherwise invert the rule
        /// silently, and GitHub's own links would start losing to numbers
        /// guessed out of sentences.
        static func stronger(_ one: Kind, _ other: Kind) -> Kind {
            one == .closes || other == .closes ? .closes : .mentions
        }
    }

    public let reference: ItemReference
    public let kind: Kind
    /// Known straight away where GitHub named the link; nil for a number
    /// read out of text, until it has been looked up.
    public let title: String?
    public let url: URL?
    /// Where the thing linked to stands, when GitHub said so with the
    /// link. Nil for a number read out of prose, which is a guess until it
    /// has been looked up.
    public let state: LinkedSummary.State?

    public var id: String { reference.id }

    public init(
        reference: ItemReference,
        kind: Kind,
        title: String? = nil,
        url: URL? = nil,
        state: LinkedSummary.State? = nil
    ) {
        self.reference = reference
        self.kind = kind
        self.title = title
        self.url = url
        self.state = state
    }

    /// Joins several findings into one list without repeating an item.
    ///
    /// Order matters: what is passed first wins the kind and keeps its
    /// title, so the graph's own answer beats a guess at the same number.
    /// Within a kind the original order is kept -- GitHub returns its links
    /// in the order they were made, and a sentence names its numbers in the
    /// order they were written.
    public static func merge(_ groups: [[ItemLink]]) -> [ItemLink] {
        var result: [ItemLink] = []
        var seen: [ItemReference: Int] = [:]

        for group in groups {
            for link in group {
                if let index = seen[link.reference] {
                    // A stronger kind, or a title where there was none.
                    let held = result[index]
                    result[index] = ItemLink(
                        reference: held.reference,
                        kind: Kind.stronger(held.kind, link.kind),
                        title: held.title ?? link.title,
                        url: held.url ?? link.url,
                        state: held.state ?? link.state
                    )
                } else {
                    seen[link.reference] = result.count
                    result.append(link)
                }
            }
        }

        // Everything that closes something first, in the order it arrived.
        return result.filter { $0.kind == .closes } + result.filter { $0.kind == .mentions }
    }
}
