import SwiftUI

/// What changed in each version, read from the file shipped in the bundle.
///
/// The repository's own `CHANGELOG.md` rather than a copy written out in
/// Swift: two versions of the same list drift, and the one nobody sees
/// while editing is the one that goes stale.
struct ChangelogView: View {
    let text: String

    var body: some View {
        ScrollView {
            MarkdownText(source: text, overflowNote: "")
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

/// Where the changelog comes from.
public enum Changelog {
    /// The shipped file, or a line saying it is missing.
    ///
    /// A bundle without it is a build that forgot to copy it, which is
    /// worth saying plainly rather than showing an empty window.
    public static func text(in bundle: Bundle = .main) -> String {
        guard
            let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "## Changelog\n\nThis build does not carry one."
        }
        return text
    }

    /// The version this build's changelog is headed by, read once.
    ///
    /// The file does not change under a running app, and this is asked
    /// every time the menu opens and every time the panel is drawn.
    public static let shipped: String? = newestVersion(in: text())

    /// The version worth pointing at, given what has already been read.
    ///
    /// Different, not newer: comparing version numbers as text puts 2.9.1
    /// above 2.10.0, and comparing them properly would be a parser written
    /// to make a dot on a menu item slightly more correct. Anything that
    /// changes the shipped version is worth a look.
    ///
    /// Nothing to announce when either side is missing. A fresh install
    /// records what it shipped with at first launch, so an absent `seen`
    /// means this is that launch -- the changelog is new to the machine,
    /// not newer than what was read on it.
    public static func unseen(shipped: String?, seen: String?) -> String? {
        guard let shipped, let seen, shipped != seen else { return nil }
        return shipped
    }

    /// The newest released version, for a window title that says which
    /// version is being read about.
    ///
    /// The first `## ` heading that begins with a digit. A heading like
    /// "Unreleased" sits above the versions in a development build, and
    /// "What's New in Unreleased" is not a title anybody wants -- the
    /// window falls back to its plain name for those.
    public static func newestVersion(in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("## ") else { continue }
            let heading = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard let first = heading.first, first.isNumber else { continue }
            return heading
        }
        return nil
    }
}
