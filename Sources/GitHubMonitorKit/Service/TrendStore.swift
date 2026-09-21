import Foundation

/// Keeps fetched trends between launches.
///
/// A year of history is the most expensive thing this app asks GitHub for,
/// and it barely changes from one day to the next. What is kept is the
/// finished points -- a median, a count and a sample size per period -- so
/// a whole repository's year is a few kilobytes rather than the thousands
/// of pull requests behind it.
public struct TrendStore: Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    /// `Application Support`, not the preferences: this is a cache of
    /// fetched data, not something the user set.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("GitHubMonitor/Trends", isDirectory: true)
    }

    /// One file per repository and resolution, so switching between weeks
    /// and months shows the other straight away instead of fetching it
    /// again.
    func url(repository: String, resolution: TrendResolution) -> URL {
        directory.appendingPathComponent("\(Self.slug(repository))-\(resolution.rawValue).json")
    }

    /// A repository name is `owner/name`, which is a path of its own.
    static func slug(_ repository: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(
            repository.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        )
    }

    public func load(repository: String, resolution: TrendResolution) -> TrendData? {
        guard let data = try? Data(contentsOf: url(repository: repository, resolution: resolution))
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(TrendData.self, from: data) else { return nil }

        // A file written for another repository or resolution would draw
        // the wrong chart silently; the name says which it is, but the
        // contents are what it is judged by.
        guard
            stored.schema == TrendData.schema,
            stored.repository == repository,
            stored.resolution == resolution
        else { return nil }
        return stored
    }

    public func save(_ data: TrendData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(data) else { return }

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // A failed write is not worth reporting: the charts are on screen
        // either way, and the only cost is fetching them again next time.
        try? encoded.write(
            to: url(repository: data.repository, resolution: data.resolution),
            options: .atomic
        )
    }
}
