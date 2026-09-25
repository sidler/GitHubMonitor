import Foundation

/// A throwaway `UserDefaults` for one test.
///
/// Every suite here needs settings of its own, and a suite name per test is
/// what keeps them from reading each other's. Naming them after a fresh UUID
/// left a property list per test behind in `~/Library/Preferences`, which
/// nothing ever deleted: a few thousand files had collected there before
/// anyone looked.
///
/// Two things fix that, and both are needed. The names are numbered rather
/// than random, so a second run reuses the first run's files instead of
/// adding to them -- that alone bounds the mess by the largest single run.
/// And the domains are removed at the end of the process, which clears the
/// files when `cfprefsd` has already flushed them. It does not always win
/// that race, which is exactly why the numbering carries the guarantee and
/// the deletion is only the tidying.
///
/// Removal waits for the end of the run rather than the end of each test: a
/// test hands its defaults to an `AppState` that outlives the call, and
/// emptying the domain sooner would empty the settings the assertions are
/// about.
enum TestDefaults {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextIndex = 0
    nonisolated(unsafe) private static var names: [String] = []
    nonisolated(unsafe) private static var isCleanupRegistered = false

    static func make() -> UserDefaults {
        lock.lock()
        let index = nextIndex
        nextIndex += 1
        lock.unlock()

        let name = "githubmonitor.tests.\(index)"
        register(name)

        let defaults = UserDefaults(suiteName: name)!
        // A reused name carries the previous run's values, and a test that
        // asserts on a fresh install would read them.
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A name without the defaults behind it, for the one test that opens
    /// its suite twice to prove a setting survives a restart. Numbered like
    /// the rest, so it reuses a file instead of leaving a new one per run.
    static func reserveName() -> String {
        lock.lock()
        let index = nextIndex
        nextIndex += 1
        lock.unlock()

        let name = "githubmonitor.tests.\(index)"
        register(name)
        UserDefaults.standard.removePersistentDomain(forName: name)
        return name
    }

    private static func register(_ name: String) {
        lock.lock()
        names.append(name)
        let needsHandler = !isCleanupRegistered
        isCleanupRegistered = true
        lock.unlock()

        if needsHandler { atexit { TestDefaults.removeAll() } }
    }

    static func removeAll() {
        lock.lock()
        let pending = names
        names = []
        lock.unlock()

        for name in pending {
            UserDefaults.standard.removePersistentDomain(forName: name)
            CFPreferencesAppSynchronize(name as CFString)
            // `removePersistentDomain` leaves the file itself behind on
            // macOS, so it has to go separately or nothing is cleaned.
            let file = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(name).plist")
            try? FileManager.default.removeItem(at: file)
        }
    }
}
