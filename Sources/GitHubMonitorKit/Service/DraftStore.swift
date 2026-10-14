import Foundation
import OSLog

/// Where a half-written review is kept between one sitting and the next.
///
/// The first thing this app writes to disk that is somebody's own words
/// rather than a cache of GitHub's. That is why it exists at all: review
/// remarks are the most expensive thing anybody produces in front of this
/// window, and losing them to a quit would be the one thing nobody
/// forgives. It is also why they are thrown away the moment they are
/// sent -- an unsent review is worth keeping, a sent one is GitHub's.
///
/// `Application Support` rather than the caches, because a cache is a
/// thing the system may delete when it is short of room, and this is not
/// that.
public struct DraftStore: Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("GitHubMonitor/Drafts", isDirectory: true)
    }

    /// One file per pull request. GitHub's node ids carry characters a
    /// path cannot, so the name is made of the ones it can.
    func url(pullRequestID: String) -> URL {
        directory.appendingPathComponent("\(Self.slug(pullRequestID)).json")
    }

    static func slug(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    public func load(pullRequestID: String) -> ReviewDraft? {
        guard let data = try? Data(contentsOf: url(pullRequestID: pullRequestID)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(ReviewDraft.self, from: data) else { return nil }

        // The name says which pull request it is; the contents are what
        // it is judged by. A file from an older shape is ignored rather
        // than half-read -- half of somebody's review is worse than none,
        // because they would not know which half.
        guard
            stored.schema == ReviewDraft.currentSchema,
            stored.pullRequestID == pullRequestID,
            !stored.isEmpty
        else { return nil }
        return stored
    }

    /// Writes it, or removes the file where there is nothing left to
    /// write: an empty draft on disk is a file that says somebody is in
    /// the middle of something when they are not.
    public func save(_ draft: ReviewDraft) {
        guard !draft.isEmpty else {
            remove(pullRequestID: draft.pullRequestID)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(draft) else { return }

        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try data.write(to: url(pullRequestID: draft.pullRequestID), options: .atomic)
        } catch {
            // Said rather than swallowed: "my remarks were gone this
            // morning" has to have an answer somewhere.
            Log.avatars.notice(
                "could not keep the draft for \(draft.pullRequestID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func remove(pullRequestID: String) {
        try? FileManager.default.removeItem(at: url(pullRequestID: pullRequestID))
    }

    /// Everything that was left half written, for putting back on screen
    /// when the app comes up.
    public func all() -> [ReviewDraft] {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard
                    let data = try? Data(contentsOf: url),
                    let stored = try? decoder.decode(ReviewDraft.self, from: data),
                    stored.schema == ReviewDraft.currentSchema,
                    !stored.isEmpty
                else { return nil }
                return stored
            }
    }
}
