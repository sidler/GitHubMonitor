import Foundation
import ServiceManagement

/// Registers the app as a login item.
///
/// `SMAppService` registers the bundle at its current path, so moving the
/// app after enabling this breaks the entry — worth knowing while the app
/// still lives in a build directory.
@MainActor
public enum LaunchAtLogin {
    public enum Failure: Error, LocalizedError {
        case rejected(String)

        public var errorDescription: String? {
            switch self {
            case .rejected(let message): message
            }
        }
    }

    /// What the system actually reports, which can differ from the stored
    /// preference if registration failed or the user removed the login item
    /// in System Settings.
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    public static func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.api.error("launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
            throw Failure.rejected(error.localizedDescription)
        }
    }

    /// Message to show when the system will not take the registration. An
    /// unsigned or self-signed app is a common reason, as is running the app
    /// from a build directory rather than /Applications.
    public static func statusMessage(after error: Error?) -> String? {
        if let error {
            return "Could not change the login item: \(error.localizedDescription)"
        }
        if requiresApproval {
            return "Waiting for approval in System Settings › General › Login Items."
        }
        return nil
    }
}
