import Foundation
import Security

/// Tiny Keychain wrapper for the one secret we hold: the Groq API key.
/// Kept in the Keychain rather than UserDefaults so the key isn't sitting in
/// plaintext in the app container.
enum KeychainStore {
    private static let service = "com.mammer55.clipkeyboard"
    private static let account = "groq_api_key"

    static var groqKey: String? {
        get { read() }
        set {
            if let v = newValue, !v.isEmpty { save(v) } else { delete() }
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func save(_ value: String) {
        let data = Data(value.utf8)
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
