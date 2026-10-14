import Foundation

/// Reading a repository's labels, and putting one on or taking one off.
///
/// Unlike approving, this is undoable: a label set by mistake is one click
/// from being unset, and nobody is notified. That is why it is the one
/// write in here with no confirmation in front of it.
///
/// Both mutations take ids and will not take names, which is why the
/// labels everywhere else in the app carry one.
public enum LabelQuery {
    /// How many of a repository's labels to ask for at a time.
    ///
    /// A large repository has hundreds, and the picker does not need them
    /// all at once -- it filters as somebody types, and GitHub does the
    /// filtering. What this number has to cover is the unfiltered list
    /// somebody scrolls when they do not know what they are looking for.
    public static let pageSize = 60

    /// The labels of one repository, optionally narrowed by what has been
    /// typed.
    ///
    /// The narrowing is GitHub's own `query:`, not a filter here: the
    /// alternative is holding every label of every repository in memory to
    /// search it, which is a lot of somebody else's taxonomy to keep
    /// around for a field that is empty most of the time.
    public static let document = """
    query($owner: String!, $name: String!, $query: String) {
      repository(owner: $owner, name: $name) {
        labels(first: \(pageSize), query: $query, orderBy: { field: NAME, direction: ASC }) {
          totalCount
          nodes { id name color }
        }
      }
    }
    """

    /// What the repository answered, and whether that was all of it.
    public struct Catalogue: Equatable, Sendable {
        public let labels: [IssueLabel]
        /// How many the repository has in all. More than were returned
        /// means the picker has to say so rather than let somebody
        /// conclude a label does not exist.
        public let total: Int

        public init(labels: [IssueLabel], total: Int) {
            self.labels = labels
            self.total = total
        }

        public var isComplete: Bool { labels.count >= total }
    }

    /// The catalogue with the ones already carried brought to the front.
    ///
    /// A repository here has a hundred and seventy labels and the list
    /// shows sixty of them, so the three an item actually carries were
    /// as likely as not to be off the bottom -- which made the one thing
    /// the picker is certain to be asked ("take this one off") the one
    /// thing it could not do without typing. Alphabetical within each
    /// group, so the rest of the list reads as it always did.
    public static func ordered(
        _ labels: [IssueLabel], carrying current: [IssueLabel]
    ) -> [IssueLabel] {
        let carried = Set(current.map(\.id))
        return labels.sorted { left, right in
            let onLeft = carried.contains(left.id)
            let onRight = carried.contains(right.id)
            if onLeft != onRight { return onLeft }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    public static func catalogue(from payload: [String: Any]) throws -> Catalogue {
        guard
            let repository = payload["repository"] as? [String: Any],
            let container = repository["labels"] as? [String: Any]
        else {
            throw GitHubError.decoding("repository has no labels")
        }
        let nodes = container["nodes"] as? [[String: Any]] ?? []
        let labels = nodes.compactMap { node -> IssueLabel? in
            guard let id = node["id"] as? String, let name = node["name"] as? String else {
                return nil
            }
            return IssueLabel(id: id, name: name, color: node["color"] as? String ?? "")
        }
        return Catalogue(
            labels: labels,
            total: container["totalCount"] as? Int ?? labels.count
        )
    }

    /// Both of these take a list and are given one of one. A pair of
    /// mutations rather than one that sets the whole set, because setting
    /// the set would quietly undo whatever somebody else added while this
    /// pane was open.
    public static let addDocument = """
    mutation($id: ID!, $labels: [ID!]!) {
      addLabelsToLabelable(input: { labelableId: $id, labelIds: $labels }) {
        clientMutationId
      }
    }
    """

    public static let removeDocument = """
    mutation($id: ID!, $labels: [ID!]!) {
      removeLabelsFromLabelable(input: { labelableId: $id, labelIds: $labels }) {
        clientMutationId
      }
    }
    """
}
