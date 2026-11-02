import Foundation

/// A whole file, for the unchanged lines a patch leaves out.
///
/// A patch carries the changed lines and three lines either side of them,
/// which is enough to see what was done and often not enough to see
/// whether it was right. The rest of the file is one request away and
/// needs no clone: a blob is named by its own contents, so the object id
/// that arrives with the patch is the whole address -- no commit, no
/// path, and a rename cannot confuse it.
///
/// GraphQL rather than the REST contents endpoint: it costs one point
/// however many files are asked for in the same query, and it answers
/// `isTruncated` rather than quietly handing back half a file.
public enum FileContentQuery {
    /// What GitHub will hand over as text. Measured rather than read: a
    /// file of 954,974 bytes came back as 511,875 characters with
    /// `isTruncated` set, and one of 1,469,012 bytes the same way.
    public static let readableBytes = 512 * 1024

    public static func document(count: Int) -> String {
        let fields = (0..<count).map { index in
            "f\(index): object(oid: $oid\(index)) { ...on Blob { "
                + "text isBinary isTruncated byteSize } }"
        }
        let parameters = (0..<count).map { "$oid\($0): GitObjectID!" }
        return """
        query($owner: String!, $name: String!, \(parameters.joined(separator: ", "))) {
          repository(owner: $owner, name: $name) {
            \(fields.joined(separator: "\n    "))
          }
        }
        """
    }

    public static func variables(
        owner: String, name: String, blobs: [String]
    ) -> [String: Any] {
        var variables: [String: Any] = ["owner": owner, "name": name]
        for (index, blob) in blobs.enumerated() { variables["oid\(index)"] = blob }
        return variables
    }

    /// What came back, keyed by the blob that was asked for.
    ///
    /// Every blob asked for is in the answer, including the ones that
    /// could not be read: a missing key would be indistinguishable from a
    /// request nobody made, and the view has to be able to stop offering
    /// to expand.
    public static func contents(
        from payload: [String: Any], blobs: [String]
    ) -> [String: FileContent] {
        let repository = payload["repository"] as? [String: Any] ?? [:]
        var found: [String: FileContent] = [:]
        for (index, blob) in blobs.enumerated() {
            found[blob] = content(from: repository["f\(index)"] as? [String: Any])
        }
        return found
    }

    static func content(from node: [String: Any]?) -> FileContent {
        // Null where the object is not a blob, or not there at all.
        guard let node else { return .missing }
        if node["isBinary"] as? Bool == true { return .binary }
        guard let text = node["text"] as? String else { return .missing }
        if node["isTruncated"] as? Bool == true {
            return .tooLarge(bytes: node["byteSize"] as? Int ?? 0)
        }
        return .text(FileText(text))
    }
}

/// A file GitHub was asked for, and what it said.
public enum FileContent: Equatable, Sendable {
    case text(FileText)
    /// There is nothing to show between the hunks of a picture.
    case binary
    /// Past what GitHub hands over as text. Said rather than shown,
    /// because half a file silently offered as the whole one is worse
    /// than no file.
    case tooLarge(bytes: Int)
    /// No such blob, which should not happen and is not worth a crash.
    case missing

    public var lines: FileText? {
        if case .text(let text) = self { return text }
        return nil
    }

    /// Why there is nothing to expand, in the words the row will carry.
    public var refusal: String? {
        switch self {
        case .text: nil
        case .binary: "This file is not text."
        case .tooLarge: "This file is too large for GitHub to send as text."
        case .missing: "GitHub did not send this file."
        }
    }
}

/// A file split into lines once, and asked about many times.
///
/// Every expansion of every gap reads from the same file, and splitting a
/// half-megabyte string on each of them is work done again for an answer
/// that cannot have changed.
public struct FileText: Equatable, Sendable {
    public let lines: [String]

    public init(_ text: String) {
        // The same carriage returns a patch is stripped of at the door.
        // A file with Windows endings would otherwise draw every line it
        // filled a gap with two lines tall.
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        // A file that ends in a newline splits into a last empty piece
        // that is not a line of the file.
        if lines.last == "" { lines.removeLast() }
        self.lines = lines
    }

    public var count: Int { lines.count }

    /// Lines `from` to `through`, counted the way a diff counts them: the
    /// first line of a file is line one.
    ///
    /// Anything outside the file is left out rather than refused. A patch
    /// and a blob can disagree -- the file may have moved on since -- and
    /// the honest answer to "show me lines 900 to 950 of an 880-line
    /// file" is the forty lines that exist.
    public func lines(from first: Int, through last: Int) -> [String] {
        guard first <= last, last >= 1, first <= count else { return [] }
        let start = max(1, first), end = min(count, last)
        guard start <= end else { return [] }
        return Array(lines[(start - 1)...(end - 1)])
    }
}
