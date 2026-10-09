import Foundation

/// Reads the links GitHub records itself out of a search result.
///
/// These are the strong kind: a "Closes #12" line GitHub understood, or a
/// link somebody made by hand in the sidebar. Everything else has to be
/// read out of text, which `ItemReferences` does.
public enum ItemLinkParser {
    /// How many links each row asks GitHub for.
    ///
    /// Its own number rather than the one `ItemReferences` reads prose
    /// with: this one sits inside a search over a hundred rows and is
    /// charged for, and raising the other because a description names more
    /// numbers than expected has no business widening it.
    public static let limit = 5

    /// The links under one connection, and how many there are altogether.
    ///
    /// The total comes from GitHub rather than from the nodes: the query
    /// asks for five, and a pull request closing eight issues should say so
    /// rather than quietly showing five.
    public static func links(
        from node: [String: Any], key: String, fallbackRepository: String
    ) -> (links: [ItemLink], total: Int) {
        guard let connection = node[key] as? [String: Any] else { return ([], 0) }
        let nodes = connection["nodes"] as? [[String: Any]] ?? []

        let links = nodes.compactMap { entry -> ItemLink? in
            guard let number = entry["number"] as? Int else { return nil }
            let repository = (entry["repository"] as? [String: Any])?["nameWithOwner"] as? String
            return ItemLink(
                reference: ItemReference(
                    repository: repository ?? fallbackRepository, number: number
                ),
                kind: .closes,
                title: entry["title"] as? String,
                url: (entry["url"] as? String).flatMap(URL.init(string:)),
                state: pullRequestState(from: entry)
            )
        }

        return (links, connection["totalCount"] as? Int ?? links.count)
    }

    /// Where a linked pull request stands.
    ///
    /// Nil rather than a guess where the query did not ask: a chip drawn
    /// green because nobody said otherwise would be a lie about something
    /// that was merged last week.
    static func pullRequestState(from entry: [String: Any]) -> LinkedSummary.State? {
        guard let raw = entry["state"] as? String else { return nil }
        switch raw {
        case "MERGED": return .merged
        case "CLOSED": return .closed
        // A draft is open, but not in the sense anybody waiting on it
        // means, so GitHub reports the two separately and so does this.
        case "OPEN": return entry["isDraft"] as? Bool == true ? .draft : .open
        default: return nil
        }
    }
}
