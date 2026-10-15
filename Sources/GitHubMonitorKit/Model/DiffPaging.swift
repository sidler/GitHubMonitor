import Foundation

/// Whether a diff is read as one long scroll or a file at a time.
///
/// A second question from `DiffLayout`, not a third answer to it: how
/// many columns a patch is laid out in and how many files are on screen
/// are independent, and somebody may well want two columns and one file.
public enum DiffPaging: String, CaseIterable, Codable, Sendable {
    /// Every file, one after another. What a review is when it is small
    /// enough to take in at once, and what this always did.
    case scroll
    /// One file, with a pager to move between them. What a review of
    /// forty-three files is, where scrolling past the one you were
    /// reading is easier than finding it again.
    case oneFile

    public var label: String {
        switch self {
        case .scroll: "All files"
        case .oneFile: "One file"
        }
    }

    public var symbolName: String {
        switch self {
        case .scroll: "list.bullet.rectangle.portrait"
        case .oneFile: "doc.plaintext"
        }
    }
}

/// Moving a file at a time through a diff.
public enum DiffPager {
    /// Where the pager stands: which file, out of how many.
    ///
    /// Counted over every file, including the ones already ticked off.
    /// Skipping those would make "4 of 6" a number that depends on what
    /// somebody did earlier, and the arrows mean something different
    /// depending on where they have been -- the same reason
    /// `DiffNavigation` hands back the next file rather than the next
    /// unread one.
    public static func place(of path: String?, in files: [ChangedFile]) -> (at: Int, of: Int)? {
        guard !files.isEmpty else { return nil }
        guard let path, let index = files.firstIndex(where: { $0.path == path }) else {
            return (1, files.count)
        }
        return (index + 1, files.count)
    }

    /// The file before this one, or nil at the first. Nil is what makes
    /// the arrow go grey: there is no wrapping, because a diff has a
    /// first file and a last one and pretending otherwise loses the one
    /// thing a pager is for -- knowing where you are.
    public static func file(before path: String?, in files: [ChangedFile]) -> String? {
        guard
            let path,
            let index = files.firstIndex(where: { $0.path == path }),
            index > 0
        else { return nil }
        return files[index - 1].path
    }

    /// The file after this one, or nil at the last.
    public static func file(after path: String?, in files: [ChangedFile]) -> String? {
        guard let path else { return files.first?.path }
        return DiffNavigation.file(after: path, in: files)
    }

    /// Which file a diff shows when it is paging: the one being read, or
    /// the first where nothing has been read yet.
    public static func shown(_ path: String?, in files: [ChangedFile]) -> ChangedFile? {
        guard let path, let file = files.first(where: { $0.path == path }) else {
            return files.first
        }
        return file
    }
}

extension Notification.Name {
    /// Asked for from the menu, answered by whichever diff is open.
    ///
    /// A notification rather than a value in the app's state: where a
    /// diff is scrolled to is written on every frame of a scroll, and
    /// putting it where the window controller can see it is what used to
    /// rebuild the whole overlay mid-scroll. This travels the other way
    /// and only when a key is pressed.
    public static let diffStepFile = Notification.Name("GitHubMonitor.diffStepFile")
}
