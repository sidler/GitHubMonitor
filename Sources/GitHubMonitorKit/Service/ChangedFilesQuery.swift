import Foundation

/// The files a pull request touches, from the REST API.
///
/// REST rather than GraphQL because the patch itself only exists there:
/// GraphQL's `files` connection carries paths and counts and no diff. It also
/// draws on a separate hourly budget from everything else the app asks for,
/// which is the reason this can be fetched whenever a pane opens.
public enum ChangedFilesQuery {
    /// One page is all that is read. A pull request past this is one nobody
    /// reviews from a side pane anyway, and the list says how many are left.
    public static let pageSize = 100

    public static func url(owner: String, name: String, number: Int) -> URL? {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/pulls/\(number)/files?per_page=\(pageSize)")
    }

    /// Splits "owner/name" the way every item in the app carries it.
    public static func repository(_ nameWithOwner: String) -> (owner: String, name: String)? {
        let parts = nameWithOwner.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    public static func files(from data: Data) throws -> [ChangedFile] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw GitHubError.decoding("the file list was not an array")
        }

        return array.compactMap(file(from:)).sorted { lhs, rhs in
            // Biggest first: in a narrow pane the useful question is where
            // the work is, and the file with four hundred changed lines is
            // not the one to make someone scroll for.
            lhs.changedLines == rhs.changedLines
                ? lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                : lhs.changedLines > rhs.changedLines
        }
    }

    static func file(from node: [String: Any]) -> ChangedFile? {
        guard let path = node["filename"] as? String else { return nil }
        return ChangedFile(
            path: path,
            additions: node["additions"] as? Int ?? 0,
            deletions: node["deletions"] as? Int ?? 0,
            change: ChangedFile.Change(apiValue: node["status"] as? String),
            // Missing for binaries and for files GitHub judged too large.
            patch: node["patch"] as? String
        )
    }
}
