import Foundation

/// Reading and writing the lists as a document, for passing them between
/// installations.
///
/// Only the lists: a query, what it is called and how it is drawn are the
/// part worth sharing. Which surfaces show a list, the repository filters
/// and the refresh interval are how one person has set their own app up,
/// and nobody should inherit those from a colleague's file.
public enum ListExchange {
    /// Written into every document. Read back only to refuse what a much
    /// later version might write -- the fields themselves are already
    /// forgiving, since `SavedList` decodes around ones it does not know.
    public static let format = 1

    public struct Document: Codable, Sendable {
        public var format: Int
        public var lists: [SavedList]

        public init(format: Int = ListExchange.format, lists: [SavedList]) {
            self.format = format
            self.lists = lists
        }
    }

    public static func encode(_ lists: [SavedList]) throws -> Data {
        let encoder = JSONEncoder()
        // Readable and stable: these files end up in a chat message or a
        // repository, where a diff of reordered keys is noise.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(lists: lists))
    }

    public static func decode(_ data: Data) throws -> [SavedList] {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw ExchangeError.unreadable
        }
        guard document.format <= format else { throw ExchangeError.tooNew(document.format) }
        guard !document.lists.isEmpty else { throw ExchangeError.empty }
        return document.lists
    }

    /// What an import would do, worked out before it does it.
    ///
    /// Lists carry their id across installations, and the three the app
    /// seeds carry the same ids for everyone -- so a colleague's file lands
    /// on top of your own "Reviews Requested" unless you are told first.
    public struct Plan: Sendable {
        /// Incoming lists whose id is already here, paired with the title
        /// they would replace.
        public let replacing: [(incoming: SavedList, existingTitle: String)]
        public let adding: [SavedList]

        public var isEmpty: Bool { replacing.isEmpty && adding.isEmpty }
        public var count: Int { replacing.count + adding.count }
    }

    public static func plan(importing incoming: [SavedList], into existing: [SavedList]) -> Plan {
        let titles = Dictionary(existing.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        var replacing: [(SavedList, String)] = []
        var adding: [SavedList] = []

        for list in incoming {
            if let title = titles[list.id] {
                replacing.append((list, title))
            } else {
                adding.append(list)
            }
        }
        return Plan(replacing: replacing, adding: adding)
    }

    /// Applies an import: a list with a known id keeps its place and takes
    /// the incoming contents, and the rest are appended in the order the
    /// file gave them.
    public static func apply(_ incoming: [SavedList], to existing: [SavedList]) -> [SavedList] {
        let byID = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var result = existing.map { byID[$0.id] ?? $0 }
        let known = Set(existing.map(\.id))
        result += incoming.filter { !known.contains($0.id) }
        return result
    }

    public enum ExchangeError: LocalizedError, Equatable {
        case unreadable
        case tooNew(Int)
        case empty

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                "That is not a list file the app can read."
            case .tooNew(let version):
                "The file was written by a newer version of the app (format \(version))."
            case .empty:
                "The file holds no lists."
            }
        }
    }
}
