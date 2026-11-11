import Foundation

/// How the unread notifications are asked for, and how far the asking goes.
///
/// GitHub's notification list is one stream in time order, with no way to
/// ask it for a kind. There is no `reason=` parameter -- `?query=reason:mention`
/// is the website's own filter, served by something that is not the API,
/// and the API ignores it along with every other spelling of the idea. So
/// the reasons somebody wants are picked out here, after the fact, and the
/// only question this leaves is how much of the stream to read.
///
/// Reading one page of it is what the app used to do, and on a busy
/// account that is a window a few hours wide: measured against one, the
/// newest fifty held 27 review requests, 21 watched-repository threads and
/// a single mention, while 55 further mentions sat further down a stream
/// 52 pages long. Nobody had read them. They had simply been pushed out of
/// the one page that was being looked at.
public enum NotificationQuery {
    /// Fifty, because GitHub will not serve more from this endpoint
    /// whatever is asked of it -- `per_page=100` comes back with fifty.
    /// Measured rather than taken from the documentation, which says the
    /// usual hundred.
    public static let pageSize = 50

    /// How many pages one poll will walk.
    ///
    /// Thirty is past the whole unread stream of the busiest account this
    /// has been run against, and the cost is bounded rather than small:
    /// thirty requests against an hourly five thousand, at a poll every
    /// few minutes. In practice almost every poll pays one of them -- an
    /// unchanged first page means nothing has moved at all, which is the
    /// short cut `fetch` takes below.
    public static let pageCap = 30

    /// The stream, newest first.
    public static func first(participating: Bool) -> URL {
        var components = URLComponents(string: "https://api.github.com/notifications")!
        components.queryItems = [
            URLQueryItem(name: "all", value: "false"),
            URLQueryItem(name: "per_page", value: "\(pageSize)"),
        ]
        if participating {
            components.queryItems?.append(
                URLQueryItem(name: "participating", value: "true")
            )
        }
        return components.url!
    }

    /// Whether the poll may ask GitHub to leave out everything the reader
    /// is not part of.
    ///
    /// `participating=true` halves the stream on a busy account -- it is
    /// what drops the threads from watched repositories, which were 1376
    /// of 2592 on the one measured. It is only safe where none of those is
    /// wanted.
    ///
    /// Team mentions are held back as well, and that is the cautious half
    /// of this. GitHub's word for the parameter is "directly participating
    /// or mentioned", and a mention of a team one belongs to is neither;
    /// the account this was measured against had none to prove it either
    /// way. Since team mentions are on by default, guessing wrong would
    /// quietly empty the list for most people -- so the saving is taken
    /// only where nobody asked for them.
    public static func participating(for reasons: Set<NotificationReason>) -> Bool {
        !reasons.contains(.subscribed) && !reasons.contains(.teamMention)
    }

    /// The next page, as GitHub itself named it.
    ///
    /// Followed verbatim rather than rebuilt from a page number: the header
    /// carries the cursor GitHub wants used, and for a repository-scoped
    /// stream it is not even the same host path that was asked for.
    ///
    /// `Link: <https://…&page=2>; rel="next", <https://…&page=52>; rel="last"`
    public static func next(from header: String?) -> URL? {
        guard let header else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";")
            guard
                pieces.count >= 2,
                pieces.dropFirst().contains(where: {
                    $0.replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "\"", with: "") == "rel=next"
                })
            else { continue }
            let raw = pieces[0].trimmingCharacters(in: .whitespaces)
            guard raw.hasPrefix("<"), raw.hasSuffix(">") else { continue }
            return URL(string: String(raw.dropFirst().dropLast()))
        }
        return nil
    }

    /// Said where the walk stopped at the cap, because a list that is
    /// short for a reason should say the reason rather than look complete.
    public static func truncationNote(pages: Int) -> String {
        "Stopped after \(pages) pages of notifications."
            + " Anything older than that is not counted here."
    }
}
