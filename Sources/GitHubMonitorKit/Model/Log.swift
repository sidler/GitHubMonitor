import OSLog

/// Subsystem loggers. Read them with:
/// `log show --predicate 'subsystem == "com.sidler.githubmonitor"' --last 5m`
public enum Log {
    private static let subsystem = "com.sidler.githubmonitor"

    public static let avatars = Logger(subsystem: subsystem, category: "avatars")
    public static let api = Logger(subsystem: subsystem, category: "api")
    public static let keychain = Logger(subsystem: subsystem, category: "keychain")
}
