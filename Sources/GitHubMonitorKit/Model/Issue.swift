import Foundation

/// A label on an issue, in the colour GitHub draws it.
public struct IssueLabel: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    /// Six hex digits, as GitHub reports them -- without a leading "#".
    public let color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }

    /// The colour as fractions of one, or nil for anything this does not
    /// understand -- a label whose colour cannot be read is still a label.
    public var components: (red: Double, green: Double, blue: Double)? {
        let hex = color
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// Whether dark text reads better on this colour than white.
    ///
    /// GitHub's palette runs from near-black to near-white, so one fixed
    /// foreground colour makes half the labels unreadable. The weights are
    /// the usual luminance ones: the eye is far more sensitive to green than
    /// to blue.
    public var prefersDarkText: Bool {
        guard let components else { return true }
        let luminance =
            0.299 * components.red + 0.587 * components.green + 0.114 * components.blue
        return luminance > 0.6
    }
}

/// The colours GitHub offers for an issue type.
///
/// A fixed palette rather than a hex value, unlike labels: the organisation
/// picks one of these eight when it defines the type.
public enum IssueTypeColor: String, Hashable, Sendable, Codable {
    case gray = "GRAY"
    case blue = "BLUE"
    case green = "GREEN"
    case yellow = "YELLOW"
    case orange = "ORANGE"
    case red = "RED"
    case pink = "PINK"
    case purple = "PURPLE"

    /// Anything GitHub adds later is drawn in the neutral colour rather than
    /// dropped: a type with no colour still has a name worth reading.
    public init(apiValue: String?) {
        self = IssueTypeColor(rawValue: apiValue ?? "") ?? .gray
    }
}

/// What kind of work an issue is: the organisation's own types, such as
/// Bug, Task, Feature or Epic.
///
/// Not a label. The type is one value per issue, set from a list the
/// organisation maintains, which is why it is worth its own place in a row
/// rather than being lost among however many labels an issue carries.
public struct IssueType: Hashable, Sendable {
    public let name: String
    public let color: IssueTypeColor

    public init(name: String, color: IssueTypeColor) {
        self.name = name
        self.color = color
    }
}

/// An issue assigned to the user.
///
/// Deliberately not a `PullRequestItem` with the pull request parts left
/// empty: an issue has no draft state, no checks and no reviewers, and a
/// shared type would carry four fields that are always zero here and make
/// every list read them.
public struct IssueItem: Identifiable, Hashable, Sendable, ListedItem {
    public let id: String
    public let number: Int
    public let title: String
    /// "owner/name"
    public let repository: String
    public let author: String
    public let authorAvatarURL: URL?
    public let url: URL
    public let createdAt: Date
    public let updatedAt: Date
    /// How much has been said on it -- the only signal in a row that
    /// something is moving.
    public let comments: Int
    public let labels: [IssueLabel]
    /// Nil when the issue is in no milestone, which most are.
    public let milestone: String?
    /// Nil where the organisation has no types, or none was set on this one.
    public let type: IssueType?

    public init(
        id: String,
        number: Int,
        title: String,
        repository: String,
        author: String,
        authorAvatarURL: URL?,
        url: URL,
        createdAt: Date? = nil,
        updatedAt: Date,
        comments: Int = 0,
        labels: [IssueLabel] = [],
        milestone: String? = nil,
        type: IssueType? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.repository = repository
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.url = url
        self.createdAt = createdAt ?? updatedAt
        self.updatedAt = updatedAt
        self.comments = comments
        self.labels = labels
        self.milestone = milestone
        self.type = type
    }

    /// The heading this issue sits under when the list is grouped by type,
    /// and the name the type filter knows it by.
    public var typeName: String { type?.name ?? Self.untyped }

    /// What an issue with no type is called, wherever one has to be named.
    public static let untyped = "No type"

    /// The timestamp the list is ordered on, as the pull request lists do it:
    /// one switch in the toolbar orders every list, since they answer the
    /// same question about different things.
    public func date(for sort: PullRequestSort) -> Date {
        switch sort {
        case .updated: updatedAt
        case .created: createdAt
        }
    }
}

/// One comment on an issue, as the detail pane shows it.
public struct IssueComment: Identifiable, Hashable, Sendable {
    public let id: String
    public let author: String
    public let avatarURL: URL?
    public let createdAt: Date
    public let body: String

    public init(id: String, author: String, avatarURL: URL?, createdAt: Date, body: String) {
        self.id = id
        self.author = author
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.body = body
    }
}

/// What the detail pane shows for one issue, fetched when its row is opened.
public struct IssueDetail: Hashable, Sendable {
    /// The issue's own text. Empty when it was opened with a title only.
    public let body: String
    /// The newest comments, oldest of those first, so the thread reads
    /// downwards the way it does on GitHub.
    public let comments: [IssueComment]
    /// Every comment, including the ones not fetched -- the pane says so
    /// rather than pretending the thread is as short as what it shows.
    public let totalComments: Int

    public init(body: String, comments: [IssueComment], totalComments: Int) {
        self.body = body
        self.comments = comments
        self.totalComments = totalComments
    }

    /// How many comments came before the ones on screen.
    public var olderComments: Int { max(0, totalComments - comments.count) }
}

/// Lifecycle of a lazily fetched issue detail.
public enum IssueDetailState: Equatable, Sendable {
    case loading
    case loaded(IssueDetail)
    case failed(String)
}

/// What the issue list is ordered by.
///
/// Its own switch rather than the pull requests': an issue can be ordered by
/// its type, and a pull request has none, so one setting for both would have
/// to offer an order that does nothing half the time.
public enum IssueSort: String, CaseIterable, Codable, Sendable {
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

/// One type present in the list, with how many issues carry it.
public struct IssueTypeTally: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    /// Nil for the bucket of issues with no type at all.
    public let color: IssueTypeColor?
    public let count: Int

    public init(name: String, color: IssueTypeColor?, count: Int) {
        self.name = name
        self.color = color
        self.count = count
    }

    public var isUntyped: Bool { color == nil }
}

/// Narrows the issue list to the repositories and the types being watched.
public enum IssueFilter {
    /// Types are stored by the names that are *hidden*, so a type the
    /// organisation adds later shows up by itself rather than waiting to be
    /// switched on.
    public static func apply(
        _ items: [IssueItem],
        hiddenTypes: Set<String>,
        repositoryFilters: [String]
    ) -> [IssueItem] {
        let matching = PullRequestFilter.matchingRepositories(
            items,
            repositoryFilters: repositoryFilters
        )
        guard !hiddenTypes.isEmpty else { return matching }
        return matching.filter { !hiddenTypes.contains($0.typeName) }
    }

    /// The types present, most-used first is *not* what this returns: the
    /// filter menu is read by name, so the order is alphabetical with the
    /// untyped bucket last, and stays put as counts change.
    public static func tallies(of items: [IssueItem]) -> [IssueTypeTally] {
        var counts: [String: Int] = [:]
        var colors: [String: IssueTypeColor] = [:]

        for item in items {
            counts[item.typeName, default: 0] += 1
            if let type = item.type { colors[type.name] = type.color }
        }

        return counts
            .map { IssueTypeTally(name: $0.key, color: colors[$0.key], count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.isUntyped != rhs.isUntyped { return rhs.isUntyped }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// The order the list takes when it is sorted by type: by type name,
    /// untyped last, and within a type by the date the rows are showing.
    public static func sorted(_ items: [IssueItem], by sort: IssueSort) -> [IssueItem] {
        items.sorted { lhs, rhs in
            if sort == .type, lhs.typeName != rhs.typeName {
                let left = lhs.type, right = rhs.type
                // An issue with no type sorts after every named one rather
                // than under "N" for "No type".
                if (left == nil) != (right == nil) { return right == nil }
                return lhs.typeName.localizedStandardCompare(rhs.typeName) == .orderedAscending
            }

            let left = lhs.date(for: sort.date)
            let right = rhs.date(for: sort.date)
            // Timestamps collide where a batch was opened at once; the id
            // keeps rows from swapping places on every refresh.
            return left == right ? lhs.id > rhs.id : left > right
        }
    }
}
