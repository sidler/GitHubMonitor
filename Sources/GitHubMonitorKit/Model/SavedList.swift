import Foundation

/// What a list is ordered by.
///
/// Shared by every list, including the two orders a pull request can be put
/// in: one switch in one place, and the type is simply not offered where
/// there is none.
public enum ListSort: String, CaseIterable, Codable, Sendable {
    case updated
    case created
    case type

    public var label: String {
        switch self {
        case .updated: "Last updated"
        case .created: "Date opened"
        case .type: "Type"
        }
    }

    public var symbolName: String {
        switch self {
        case .updated: "clock.arrow.circlepath"
        case .created: "calendar"
        case .type: "tag"
        }
    }

    /// Which date a row prints under this order. Ordering by type still
    /// leaves rows to date-stamp, and the last activity is the useful one.
    public var date: PullRequestSort {
        self == .created ? .created : .updated
    }
}

/// What a list is made of. A list shows one kind of thing: the rows, the
/// legend, the ordering and the detail pane all differ between them, and a
/// mixed list would have to hedge on all four.
public enum ListContent: String, CaseIterable, Codable, Sendable {
    case pullRequests
    case issues

    public var label: String {
        switch self {
        case .pullRequests: "Pull requests"
        case .issues: "Issues"
        }
    }

    /// The qualifier a query needs to return this kind, offered when a list
    /// is created.
    public var queryPrefix: String {
        switch self {
        case .pullRequests: "is:pr is:open archived:false "
        case .issues: "is:issue is:open archived:false "
        }
    }

    public var symbolName: String {
        switch self {
        case .pullRequests: StatusBarTitleBuilder.pullRequestSymbol
        case .issues: StatusBarTitleBuilder.issueSymbol
        }
    }

    /// The orders this kind can be put in. Only issues carry a type.
    public var sorts: [ListSort] {
        switch self {
        case .pullRequests: [.updated, .created]
        case .issues: ListSort.allCases
        }
    }

    /// How its rows can be split into sections.
    public var groupings: [ListGrouping] {
        switch self {
        case .pullRequests: ListGrouping.forPullRequests
        case .issues: ListGrouping.forIssues
        }
    }
}

/// One list in the sidebar: a title, the searches behind it, and how it is
/// shown.
///
/// The three lists the app started with are these too -- seeded on first
/// launch and editable like any other. A built-in list that behaved
/// differently from one you made yourself would be a second thing to learn
/// for no reason.
public struct SavedList: Identifiable, Hashable, Codable, Sendable {
    /// Stable across renames: the visibility switches, the per-list view
    /// settings and the fetched results are all keyed by it.
    public let id: String
    public var title: String
    /// GitHub search syntax, one search per line.
    ///
    /// Several lines because GitHub reads repeated qualifiers of one kind as
    /// AND: "requested from me" and "requested from one of my teams" cannot
    /// be one search, and that is the app's own first list. Lines are run
    /// separately and merged, so an item found by two of them appears once.
    public var query: String
    public var content: ListContent
    /// Nil falls back to the content's own symbol.
    public var symbolName: String?
    public var grouping: ListGrouping
    public var sort: ListSort
    /// Issue types left out, by name. Only meaningful for issue lists.
    public var hiddenTypes: Set<String>
    /// Whether draft pull requests are shown. Per list rather than per app:
    /// a queue of what to review wants them out of the way, and a list of
    /// one's own work is mostly drafts.
    public var includeDrafts: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        query: String,
        content: ListContent,
        symbolName: String? = nil,
        grouping: ListGrouping = .flat,
        sort: ListSort = .updated,
        hiddenTypes: Set<String> = [],
        includeDrafts: Bool = false
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.content = content
        self.symbolName = symbolName
        self.grouping = grouping
        self.sort = sort
        self.hiddenTypes = hiddenTypes
        self.includeDrafts = includeDrafts
    }

    /// Written by hand because the synthesised one throws on a key that is
    /// not there, and every field past `content` was added after lists were
    /// first stored. A list saved before a field existed would otherwise
    /// fail to decode -- and a failed decode reseeds the sidebar, which
    /// would throw away the lists someone had made.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        query = try container.decode(String.self, forKey: .query)
        content = try container.decode(ListContent.self, forKey: .content)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName)
        grouping = try container.decodeIfPresent(ListGrouping.self, forKey: .grouping) ?? .flat
        sort = try container.decodeIfPresent(ListSort.self, forKey: .sort) ?? .updated
        hiddenTypes = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenTypes) ?? []
        includeDrafts = try container.decodeIfPresent(Bool.self, forKey: .includeDrafts) ?? false
    }

    public var symbol: String { symbolName ?? content.symbolName }

    /// The searches behind this list, one per non-empty line.
    public var queryLines: [String] {
        query
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var isRunnable: Bool { !queryLines.isEmpty && !title.isEmpty }

    /// The ids the app seeds on first launch. Fixed strings rather than
    /// fresh ones, so settings written before lists existed -- which of them
    /// appear in the menu bar, how each was sorted -- still find their list.
    public enum Seed {
        public static let reviews = "reviews"
        public static let authored = "authored"
        public static let issues = "issues"
    }

    /// The lists a fresh install starts with, carrying over what was
    /// configured for them before lists were editable.
    public static func seeds(
        grouping: ListGrouping,
        issueSettings: (ListGrouping, ListSort, Set<String>)
    ) -> [SavedList] {
        ListPresets.seeded.map { preset in
            switch preset.content {
            case .pullRequests:
                preset.list(id: preset.id, grouping: grouping)
            case .issues:
                preset.list(
                    id: preset.id,
                    grouping: issueSettings.0,
                    sort: issueSettings.1,
                    hiddenTypes: issueSettings.2
                )
            }
        }
    }

    /// The symbols offered in the picker's grid.
    ///
    /// A set that suits lists of work rather than a catalogue: any other SF
    /// Symbol can be typed in by name, so this is the shortcut, not the
    /// limit.
    public static let symbolChoices = [
        StatusBarTitleBuilder.pullRequestSymbol, StatusBarTitleBuilder.issueSymbol,
        "checkmark.seal", "checkmark.circle", "xmark.octagon", "exclamationmark.triangle",
        "person.crop.circle", "person.2", "eye", "bubble.left",
        "star", "flame", "bolt", "sparkles",
        "clock", "calendar", "hourglass", "timer",
        "tag", "flag", "bookmark", "pin",
        "tray.full", "shippingbox", "hammer", "wrench.and.screwdriver",
        "ant", "ladybug", "lifepreserver", "cross.case",
        "lock", "shield", "key", "seal",
        "chart.bar", "chart.line.uptrend.xyaxis", "gauge", "speedometer",
        "folder", "doc.text", "book.closed", "graduationcap",
    ]
}
