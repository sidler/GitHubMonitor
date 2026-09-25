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
