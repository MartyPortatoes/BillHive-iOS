import Foundation
import Security

// MARK: - Keychain Helper

/// Minimal Keychain wrapper for storing the SelfHive API key.
///
/// Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
///   - The item is only readable while the device is unlocked.
///   - It does NOT migrate to a new device via iCloud Backup or device transfer.
///   - It does NOT sync via iCloud Keychain.
///
/// We deliberately don't put the API key in `UserDefaults` — the prefs plist
/// gets backed up to iCloud/iTunes and is readable in plaintext on jailbroken
/// devices. Bearer tokens belong in Keychain.
enum KeychainHelper {

    // MARK: - Keys

    /// Storage account name for the SelfHive API key. Single global slot per app
    /// — saving overwrites any existing value. Bundle-scoped (default), so only
    /// this app can read it.
    private static let apiKeyAccount = "selfhive.api_key"

    // MARK: - API Key

    /// Persists the API key. Pass an empty string to clear it.
    /// Returns `true` on success, `false` if the Keychain operation failed
    /// (rare — disk full, malformed query, etc.).
    @discardableResult
    static func saveApiKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return deleteApiKey() }
        let data = Data(key.utf8)

        // Try update-in-place first; falls through to insert if not present.
        let lookup: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: apiKeyAccount,
        ]
        let updates: [String: Any] = [
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        // Insert
        var add = lookup
        add[kSecValueData as String]      = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// Returns the persisted API key, or `nil` if none is stored.
    static func loadApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key  = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    /// Removes the persisted API key. Returns `true` on success or if no key
    /// was stored (idempotent).
    @discardableResult
    static func deleteApiKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: apiKeyAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Returns the first 12 characters of the stored key for display purposes
    /// (e.g. "bh_live_a8f3"), or `nil` if no key is stored.
    static func apiKeyPrefix() -> String? {
        guard let key = loadApiKey(), !key.isEmpty else { return nil }
        return String(key.prefix(12))
    }
}
