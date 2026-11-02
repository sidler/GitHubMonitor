import Foundation

/// The files a pull request touches, from the REST API.
///
/// REST rather than GraphQL because the patch itself only exists there:
/// GraphQL's `files` connection carries paths and counts and no diff. It also
/// draws on a separate hourly budget from everything else the app asks for,
/// which is the reason this can be fetched whenever a pane opens.
public enum ChangedFilesQuery {
    /// GitHub's most per page.
    public static let pageSize = 100

    /// How many files are read before the overlay stops and says there are
    /// more. A pull request past this is not one anybody reviews from a
    /// side pane, and every page is another request.
    public static let maximumFiles = 300

    public static func url(owner: String, name: String, number: Int, page: Int = 1) -> URL? {
        URL(
            string: "https://api.github.com/repos/\(owner)/\(name)/pulls/\(number)/files"
                + "?per_page=\(pageSize)&page=\(page)"
        )
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

        return array.compactMap(file(from:))
    }

    /// By path, which is the order the diff reads in and the order GitHub
    /// shows.
    ///
    /// This used to put the biggest change first, on the reasoning that in
    /// a narrow pane the useful question is where the work is. But the
    /// list in that pane is a way into the diff -- each row opens it at
    /// that file -- and the tree beside the diff is in path order, so the
    /// two disagreed about what came after what. A list you navigate by
    /// has to match the thing it navigates.
    ///
    /// Applied to the whole set rather than page by page, or the second
    /// page would start over at the top of the alphabet.
    public static func ordered(_ files: [ChangedFile]) -> [ChangedFile] {
        files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// A patch with its carriage returns taken off, once, here.
    ///
    /// A file written with Windows endings arrives as a patch whose every
    /// line ends `\r\n`, and the `\r` survives the split into lines --
    /// where the text view draws it as a line terminator of its own. Every
    /// row of such a file came out two lines tall, at every font size,
    /// which is why it only ever happened to some diffs.
    ///
    /// Done at the door rather than in each of the four places a patch is
    /// read: the caches are keyed by the patch string, so a patch
    /// normalised later would be two keys for one file.
    static func unixEndings(_ patch: String) -> String {
        patch.replacingOccurrences(of: "\r\n", with: "\n")
    }

    static func file(from node: [String: Any]) -> ChangedFile? {
        guard let path = node["filename"] as? String else { return nil }
        return ChangedFile(
            path: path,
            additions: node["additions"] as? Int ?? 0,
            deletions: node["deletions"] as? Int ?? 0,
            change: ChangedFile.Change(apiValue: node["status"] as? String),
            // Missing for binaries and for files GitHub judged too large.
            patch: (node["patch"] as? String).map(unixEndings),
            // Comes free with the patch, in the same answer. It is what
            // the unchanged lines around the hunks are fetched by.
            blob: node["sha"] as? String
        )
    }
}
