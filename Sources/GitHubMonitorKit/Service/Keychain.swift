import Foundation
import Security

/// The GitHub token, stored in the login keychain.
///
/// Keychain access control is tied to the application's code signature, which
/// is why the build signs with a stable identity — see
/// Scripts/create-signing-certificate.sh.
public enum Keychain {
    public enum Failure: Error, LocalizedError {
        case status(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .status(let code):
                let message = SecCopyErrorMessageString(code, nil) as String?
                return message ?? "Keychain error \(code)"
            }
        }
    }

    private static let service = "com.sidler.githubmonitor"
    private static let account = "github-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func readToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            Log.keychain.error("read failed with status \(status)")
            throw Failure.status(status)
        }
    }

    public static func writeToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else { return }

        // Update in place when an entry exists, so the item's access control
        // list — and the user's "always allow" decision — survives.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            Log.keychain.error("update failed with status \(updateStatus)")
            throw Failure.status(updateStatus)
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Log.keychain.error("add failed with status \(addStatus)")
            throw Failure.status(addStatus)
        }
    }

    public static func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.status(status)
        }
    }
}
