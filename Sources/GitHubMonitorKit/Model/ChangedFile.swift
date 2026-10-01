import CryptoKit
import Foundation

/// One file a pull request touches.
public struct ChangedFile: Identifiable, Hashable, Sendable {
    public enum Change: String, Hashable, Sendable {
        case added
        case modified
        case removed
        case renamed
        case other

        public init(apiValue: String?) {
            switch apiValue {
            case "added", "copied": self = .added
            case "modified", "changed": self = .modified
            case "removed": self = .removed
            case "renamed": self = .renamed
            default: self = .other
            }
        }

        public var symbolName: String {
            switch self {
            case .added: "plus.circle"
            case .modified: "pencil.circle"
            case .removed: "minus.circle"
            case .renamed: "arrow.right.circle"
            case .other: "circle"
            }
        }

        public var label: String {
            switch self {
            case .added: "Added"
            case .modified: "Modified"
            case .removed: "Removed"
            case .renamed: "Renamed"
            case .other: "Changed"
            }
        }
    }

    public var id: String { path }
    public let path: String
    public let additions: Int
    public let deletions: Int
    public let change: Change
    /// Absent for a binary file, and for one GitHub judged too large to send.
    public let patch: String?

    public init(path: String, additions: Int, deletions: Int, change: Change, patch: String?) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
        self.change = change
        self.patch = patch
    }

    public var changedLines: Int { additions + deletions }

    /// The file's own place in the pull request's diff on GitHub, which
    /// anchors on the SHA-256 of the path.
    public func url(pullRequest: URL) -> URL? {
        let digest = SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return URL(string: pullRequest.absoluteString + "/files#diff-\(digest)")
    }

    /// The language the patch is written in, for colouring it.
    public var language: CodeLanguage? { CodeLanguage.forFile(path) }

    /// The part of the path worth reading in a narrow pane: the name, and the
    /// directory above it where there is one.
    public var shortPath: String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return path }
        return parts.suffix(2).joined(separator: "/")
    }
}

/// Lifecycle of the file list, which is fetched beside the rest of a detail.
public enum ChangedFilesState: Equatable, Sendable {
    case loading
    case loaded([ChangedFile])
    case failed(String)
}

/// Whether this person has ticked a file off while reviewing.
///
/// GitHub's own three answers, not two. `dismissed` is the one worth
/// keeping apart: it means the file was ticked and has changed since, so
/// the tick was taken back. "Looked at, but not at this" is a different
/// thing from "not looked at", and it is the one a reviewer most needs to
/// see.
public enum FileViewedState: String, Hashable, Sendable {
    case unviewed
    case viewed
    case dismissed

    public init(apiValue: String?) {
        switch apiValue {
        case "VIEWED": self = .viewed
        case "DISMISSED": self = .dismissed
        default: self = .unviewed
        }
    }

    /// Whether the patch is folded away. Only a plain tick folds it: a
    /// dismissed file is exactly the one to read again.
    public var isFolded: Bool { self == .viewed }

    public var label: String {
        switch self {
        case .unviewed: "Not viewed"
        case .viewed: "Viewed"
        case .dismissed: "Changed since you viewed it"
        }
    }

    public var symbolName: String {
        switch self {
        case .unviewed: "square"
        case .viewed: "checkmark.square.fill"
        case .dismissed: "exclamationmark.square"
        }
    }
}

/// Where the diff goes next when a file is ticked off.
///
/// Folding a file takes height out of the column above where the reader is
/// looking, so the offset that was the start of the following file becomes
/// somewhere in the middle of it. Landing mid-patch is worse than not
/// folding at all: the lines above are gone from view and nothing says they
/// were skipped. The cure is to say where to land rather than let the
/// shrinking layout decide.
public enum DiffNavigation {
    /// The file after `path`, or nil if it is the last one.
    ///
    /// The next file as listed, not the next unviewed one. Skipping ahead
    /// over files already ticked would be a second guess about where the
    /// reader wants to be, and one they did not ask for.
    public static func file(after path: String, in files: [ChangedFile]) -> String? {
        guard
            let index = files.firstIndex(where: { $0.path == path }),
            files.indices.contains(index + 1)
        else { return nil }
        return files[index + 1].path
    }

    /// Where to leave the scroll when `ticked` is ticked off while `showing`
    /// is the file at the top of the column, or nil to leave it alone.
    ///
    /// Nil for everything except folding away the file being read. Ticking
    /// something further down in passing, or unfolding one, should not move
    /// the page -- a jump nobody asked for is its own kind of lost place.
    public static func destination(
        ticking ticked: String,
        folding: Bool,
        showing: String?,
        in files: [ChangedFile]
    ) -> String? {
        guard folding, showing == ticked else { return nil }
        // The last file has nothing after it, so it keeps itself: the tick
        // ends somewhere deliberate rather than wherever the shrinking
        // layout happens to leave it.
        return file(after: ticked, in: files) ?? ticked
    }
}
