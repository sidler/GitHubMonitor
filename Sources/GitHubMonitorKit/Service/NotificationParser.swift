import Foundation

/// Turns the REST notifications payload into model objects.
public enum NotificationParser {
    public static func notifications(from data: Data) throws -> [NotificationItem] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw GitHubError.decoding("notifications response was not a list")
        }
        return array.compactMap(notification(from:))
    }

    static func notification(from entry: [String: Any]) -> NotificationItem? {
        guard
            let id = entry["id"] as? String,
            let subject = entry["subject"] as? [String: Any],
            let title = subject["title"] as? String
        else { return nil }

        let repository = entry["repository"] as? [String: Any]
        let owner = repository?["owner"] as? [String: Any]
        let subjectURL = (subject["url"] as? String).flatMap(URL.init(string:))

        return NotificationItem(
            id: id,
            title: title,
            repository: repository?["full_name"] as? String ?? "?",
            avatarURL: (owner?["avatar_url"] as? String).flatMap(URL.init(string:)),
            reason: NotificationReason(apiValue: entry["reason"] as? String ?? ""),
            updatedAt: GitHubDate.date(from: entry["updated_at"] as? String),
            subjectType: subject["type"] as? String ?? "Unknown",
            latestCommentAPIURL: (subject["latest_comment_url"] as? String).flatMap(URL.init(string:)),
            subjectAPIURL: subjectURL
        )
    }

    /// The comment behind `latest_comment_url`: who wrote it and what it
    /// says.
    ///
    /// Both come from the same response, which is why the sender is known
    /// for a notification only once its comment has been read.
    public static func comment(from data: Data) -> CommentPreview {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .none
        }
        return CommentPreview(author: author(from: object), body: body(from: object))
    }

    static func body(from object: [String: Any]) -> String? {
        // Issue and review comments carry "body"; a commit carries "message".
        let body = object["body"] as? String ?? object["message"] as? String
        guard let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return body
    }

    static func author(from object: [String: Any]) -> CommentAuthor? {
        // A comment names its "user"; a commit names an "author", who is a
        // git identity and only sometimes a GitHub account.
        if let user = object["user"] as? [String: Any], let login = user["login"] as? String {
            return CommentAuthor(
                login: login,
                avatarURL: (user["avatarUrl"] as? String ?? user["avatar_url"] as? String)
                    .flatMap(URL.init(string:))
            )
        }
        if let commit = object["author"] as? [String: Any] {
            if let login = commit["login"] as? String {
                return CommentAuthor(
                    login: login,
                    avatarURL: (commit["avatar_url"] as? String).flatMap(URL.init(string:))
                )
            }
            if let name = commit["name"] as? String {
                return CommentAuthor(login: name, avatarURL: nil)
            }
        }
        return nil
    }
}

/// Maps a notification's API URL to the page a person would open.
///
/// The notifications API carries no browser URL, and resolving one by
/// fetching the subject would cost a request per row. The mapping is
/// mechanical, so it is done locally instead.
public enum NotificationLink {
    public static func browserURL(for item: NotificationItem) -> URL? {
        guard let api = item.subjectAPIURL else {
            // Without a subject there is still a repository to fall back on.
            return URL(string: "https://github.com/\(item.repository)")
        }
        return browserURL(fromAPI: api) ?? URL(string: "https://github.com/\(item.repository)")
    }

    static func browserURL(fromAPI url: URL) -> URL? {
        let components = url.path.split(separator: "/").map(String.init)
        // /repos/{owner}/{repo}/{kind}/{id}
        guard components.count >= 5, components[0] == "repos" else { return nil }

        let owner = components[1]
        let repository = components[2]
        let kind = components[3]
        let identifier = components[4]

        // The API says "pulls", the website says "pull".
        let path: String
        switch kind {
        case "pulls": path = "pull"
        case "issues": path = "issues"
        case "commits": path = "commit"
        case "releases": path = "releases/tag"
        case "discussions": path = "discussions"
        default: path = kind
        }

        return URL(string: "https://github.com/\(owner)/\(repository)/\(path)/\(identifier)")
    }
}
