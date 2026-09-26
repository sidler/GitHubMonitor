import Foundation

/// One issue or pull request, named by repository and number.
///
/// Number and repository rather than a node id: a number read out of a
/// title or a sentence is all there is to go on, and it is enough to ask
/// GitHub for the rest.
public struct ItemReference: Hashable, Sendable, Identifiable, Comparable {
    /// "owner/name"
    public let repository: String
    public let number: Int

    public var id: String { "\(repository)#\(number)" }

    public init(repository: String, number: Int) {
        self.repository = repository
        self.number = number
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.repository == rhs.repository
            ? lhs.number < rhs.number
            : lhs.repository.localizedStandardCompare(rhs.repository) == .orderedAscending
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
    public enum Kind: Hashable, Sendable, Comparable {
        case closes
        case mentions
    }

    public let reference: ItemReference
    public let kind: Kind
    /// Known straight away where GitHub named the link; nil for a number
    /// read out of text, until it has been looked up.
    public let title: String?
    public let url: URL?

    public var id: String { reference.id }

    public init(reference: ItemReference, kind: Kind, title: String? = nil, url: URL? = nil) {
        self.reference = reference
        self.kind = kind
        self.title = title
        self.url = url
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
                        kind: min(held.kind, link.kind),
                        title: held.title ?? link.title,
                        url: held.url ?? link.url
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
