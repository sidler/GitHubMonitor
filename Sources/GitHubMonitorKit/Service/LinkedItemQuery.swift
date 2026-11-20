import Foundation

/// Looks up issues and pull requests by number.
///
/// A number read out of a title or a sentence is all there is to go on, so
/// the lookup goes through `repository(owner:name:){ issueOrPullRequest }`
/// rather than a node id. Everything wanted at once, aliased into one
/// document: a search costs a point whatever it carries back, and so does
/// this, so asking for eight links separately would cost eight times what
/// asking for them together does.
public enum LinkedItemQuery {
    /// How many are looked up in one request. Past this the panel is a
    /// list rather than an answer.
    public static let maximumLookups = 12

    /// Asked for only where the token can see boards.
    ///
    /// ProjectsV2 sits behind its own scope, and a classic token granted
    /// `repo` alone is not granted it. Asking anyway does not merely
    /// leave the field empty: GitHub refuses the whole query, so the
    /// panel would stop showing linked tickets at all for anybody who
    /// has not minted a new token.
    public static let projectScope = "read:project"

    /// And the column within it needs one more.
    ///
    /// A board's columns are a field of the project, and on an
    /// organisation's board reading what that field is called is reading
    /// something about the organisation. GitHub answers a token without
    /// it by refusing the whole query -- naming the `name` field, not
    /// `projectItems` -- so the column is asked for separately from the
    /// board it belongs to.
    public static let columnScope = "read:org"

    static func projectFields(columns: Bool) -> String {
        let status = columns ? """

            # The column, which is the thing a board is read for. Named
            # rather than taken by position: a board's fields can be in
            # any order, and every board has this one.
            status: fieldValueByName(name: "Status") {
              ... on ProjectV2ItemFieldSingleSelectValue { name optionId }
            }
        """ : ""
        // The field itself, for the ids a move needs and the columns to
        // offer. Asked of the project, not of the item's value: an issue
        // that has no column yet has no value to read them off, and that
        // is the one somebody most wants to move.
        let field = columns ? """

                  field(name: "Status") {
                    ... on ProjectV2SingleSelectField { id options { id name color } }
                  }
        """ : ""
        return """
            projectItems(first: 5, includeArchived: false) {
              nodes {
                id
                project { id title\(field) }\(status)
              }
            }
        """
    }

    public static func document(
        for references: [ItemReference], projects: Bool = false, columns: Bool = false
    ) -> String? {
        let wanted = asked(references)
        guard !wanted.isEmpty else { return nil }

        // Grouped by repository, because that is how the query nests.
        var order: [String] = []
        var byRepository: [String: [ItemReference]] = [:]
        for reference in wanted {
            if byRepository[reference.repository] == nil { order.append(reference.repository) }
            byRepository[reference.repository, default: []].append(reference)
        }

        var repositories: [String] = []
        for (index, name) in order.enumerated() {
            let parts = name.split(separator: "/")
            guard parts.count == 2 else { continue }
            let fields = (byRepository[name] ?? []).map { reference in
                "    \(alias(for: reference)): issueOrPullRequest(number: \(reference.number)) "
                    + "{ ...Summary }"
            }
            repositories.append("""
              r\(index): repository(owner: \(PullRequestQuery.jsonString(String(parts[0]))), \
            name: \(PullRequestQuery.jsonString(String(parts[1])))) {
            \(fields.joined(separator: "\n"))
              }
            """)
        }
        guard !repositories.isEmpty else { return nil }

        return """
        query {
          rateLimit { limit remaining resetAt cost }
        \(repositories.joined(separator: "\n"))
        }
        \(summaryFragment(projects: projects, columns: columns))
        """
    }

    /// Everything wanted, split into requests GitHub will take.
    ///
    /// Splitting rather than truncating: a pull request can name more
    /// numbers than one request holds -- five GitHub linked, five off the
    /// title, five out of the description -- and dropping the rest meant
    /// they were recorded as "not there" without ever having been asked
    /// about.
    public static func batches(_ references: [ItemReference]) -> [[ItemReference]] {
        var seen = Set<ItemReference>()
        let unique = references.filter { seen.insert($0).inserted }
        return stride(from: 0, to: unique.count, by: maximumLookups).map { start in
            Array(unique[start..<min(start + maximumLookups, unique.count)])
        }
    }

    /// What one request actually asks for: no repeats, and no more than
    /// fits. The same number twice in one repository would produce the same
    /// alias twice, which GitHub rejects outright.
    static func asked(_ references: [ItemReference]) -> [ItemReference] {
        batches(references).first ?? []
    }

    /// An alias GitHub accepts and the parser can read the reference back
    /// out of. Dots and slashes are not allowed in a GraphQL name, so the
    /// repository is carried by position and only the number is in here.
    static func alias(for reference: ItemReference) -> String {
        "n\(reference.number)"
    }

    static func summaryFragment(projects: Bool, columns: Bool) -> String {
        let boards = projects ? projectFields(columns: columns) : ""
        return """
    fragment Summary on IssueOrPullRequest {
      ... on Issue {
        __typename
        number
        title
        url
        state
        # Closed as done and closed as not planned are different answers.
        stateReason
        createdAt
        updatedAt
        body
        repository { nameWithOwner }
        author { login avatarUrl }
        assignees(first: 5) { nodes { login } }
    \(boards)
        comments { totalCount }
        labels(first: \(IssueQuery.labelLimit)) { nodes { id name color } }
      }
      ... on PullRequest {
        __typename
        number
        title
        url
        state
        isDraft
        createdAt
        updatedAt
        body
        repository { nameWithOwner }
        author { login avatarUrl }
        assignees(first: 5) { nodes { login } }
    \(boards)
        comments { totalCount }
        additions
        deletions
        changedFiles
        reviewDecision
        commits(last: 1) {
          nodes { commit { statusCheckRollup { state } } }
        }
      }
    }
    """
    }

    /// What came back, keyed by reference.
    ///
    /// Every reference asked for appears in the answer, as a summary or as
    /// `missing`: a caller that only heard about the ones that resolved
    /// would keep asking for the others for the rest of the session.
    public static func summaries(
        from payload: [String: Any], asked references: [ItemReference]
    ) -> [ItemReference: LinkedSummaryState] {
        var result: [ItemReference: LinkedSummaryState] = [:]
        let wanted = asked(references)

        // Repositories are addressed by position, so the grouping has to be
        // rebuilt the same way the document built it.
        var order: [String] = []
        var byRepository: [String: [ItemReference]] = [:]
        for reference in wanted {
            if byRepository[reference.repository] == nil { order.append(reference.repository) }
            byRepository[reference.repository, default: []].append(reference)
        }

        for (index, name) in order.enumerated() {
            let repository = payload["r\(index)"] as? [String: Any]
            for reference in byRepository[name] ?? [] {
                let node = repository?[alias(for: reference)] as? [String: Any]
                result[reference] = node.flatMap { summary(from: $0, reference: reference) }
                    .map(LinkedSummaryState.loaded) ?? .missing
            }
        }

        return result
    }

    static func summary(from node: [String: Any], reference: ItemReference) -> LinkedSummary? {
        guard
            let title = node["title"] as? String,
            let urlString = node["url"] as? String,
            let url = URL(string: urlString)
        else { return nil }

        let author = node["author"] as? [String: Any]
        let isPullRequest = node["__typename"] as? String == "PullRequest"

        return LinkedSummary(
            // The repository is taken from the answer where it is given:
            // asking for `octo/platform#1` and being answered by a
            // transferred issue should show where it actually lives.
            reference: ItemReference(
                repository: (node["repository"] as? [String: Any])?["nameWithOwner"] as? String
                    ?? reference.repository,
                number: node["number"] as? Int ?? reference.number
            ),
            kind: isPullRequest ? .pullRequest : .issue,
            state: state(from: node, isPullRequest: isPullRequest),
            title: title,
            author: author?["login"] as? String ?? "ghost",
            authorAvatarURL: (author?["avatarUrl"] as? String).flatMap(URL.init(string:)),
            assignees: logins(in: node["assignees"]),
            projects: boards(in: node["projectItems"]),
            url: url,
            createdAt: GitHubDate.date(from: node["createdAt"] as? String),
            updatedAt: GitHubDate.date(from: node["updatedAt"] as? String),
            body: node["body"] as? String ?? "",
            comments: (node["comments"] as? [String: Any])?["totalCount"] as? Int ?? 0,
            labels: isPullRequest ? [] : IssueParser.labels(from: node),
            checks: isPullRequest ? PullRequestParser.checks(from: node) : nil,
            reviewDecision: isPullRequest
                ? PullRequestParser.reviewDecision(node["reviewDecision"] as? String)
                : nil,
            changedFiles: node["changedFiles"] as? Int,
            additions: node["additions"] as? Int,
            deletions: node["deletions"] as? Int
        )
    }

    /// The boards out of a `projectItems` connection. An item with no
    /// title is one the token may not read, which is nothing to draw.
    static func boards(in connection: Any?) -> [LinkedProject] {
        ((connection as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
            .compactMap { item in
                let project = item["project"] as? [String: Any]
                guard let title = project?["title"] as? String else { return nil }
                let field = project?["field"] as? [String: Any]
                return LinkedProject(
                    title: title,
                    status: (item["status"] as? [String: Any])?["name"] as? String,
                    projectID: project?["id"] as? String,
                    itemID: item["id"] as? String,
                    statusFieldID: field?["id"] as? String,
                    statusOptionID: (item["status"] as? [String: Any])?["optionId"] as? String,
                    statuses: (field?["options"] as? [[String: Any]] ?? []).compactMap {
                        guard let id = $0["id"] as? String, let name = $0["name"] as? String
                        else { return nil }
                        return ProjectStatus(
                            id: id, name: name,
                            color: IssueTypeColor(apiValue: $0["color"] as? String)
                        )
                    }
                )
            }
    }

    /// The logins out of a `{ nodes { login } }` connection.
    static func logins(in connection: Any?) -> [String] {
        ((connection as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
            .compactMap { $0["login"] as? String }
    }

    static func state(from node: [String: Any], isPullRequest: Bool) -> LinkedSummary.State {
        let raw = node["state"] as? String
        guard isPullRequest else {
            if raw == "CLOSED" {
                return node["stateReason"] as? String == "NOT_PLANNED" ? .notPlanned : .closed
            }
            return .open
        }
        switch raw {
        case "MERGED": return .merged
        case "CLOSED": return .closed
        default: return node["isDraft"] as? Bool == true ? .draft : .open
        }
    }
}
