import Foundation
import Security

/// Where Studio tokens live: one per blyg origin, never in the bundle, logs, files or backups.
nonisolated protocol TokenStore: Sendable {
    func token(for origin: URL) -> String?
    func save(_ token: String, for origin: URL) throws
    func remove(for origin: URL)
}

nonisolated enum TokenStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// The Keychain, in an access group the Share extension can also read.
nonisolated struct KeychainTokenStore: TokenStore {
    static let service = "net.jdbb.blyg.studio-token"
    /// Must match `keychain-access-groups` in Blyg.entitlements ($(AppIdentifierPrefix) is the team ID plus a dot).
    static let accessGroup = "K24RHPX75P.net.jdbb.blyg.shared"

    private func query(_ origin: URL) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: origin.absoluteString,
            kSecAttrAccessGroup as String: Self.accessGroup,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func token(for origin: URL) -> String? {
        var q = query(origin)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String, for origin: URL) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(query(origin) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw TokenStoreError.keychain(update) }
        var add = query(origin)
        add[kSecValueData as String] = data
        // Readable after the first unlock (so the Share extension works), never synced or restored to another phone.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.keychain(status) }
    }

    func remove(for origin: URL) {
        SecItemDelete(query(origin) as CFDictionary)
    }
}

/// For tests, UI tests and screenshots: forgets everything when the app quits.
nonisolated final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [URL: String] = [:]

    func token(for origin: URL) -> String? { lock.withLock { tokens[origin] } }
    func save(_ token: String, for origin: URL) throws { lock.withLock { tokens[origin] = token } }
    func remove(for origin: URL) { _ = lock.withLock { tokens.removeValue(forKey: origin) } }
}
