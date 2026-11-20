import Foundation
import Security

/// A blyg this phone can post to, as the Share extension sees it: no app storage needed, just the Keychain.
nonisolated struct Connection: Sendable, Equatable, Identifiable, Hashable {
    var origin: URL
    var title: String
    var api: URL
    var id: URL { origin }
}

/// Where Studio tokens live: one per blyg origin, never in the bundle, logs, files or backups.
nonisolated protocol TokenStore: Sendable {
    func token(for origin: URL) -> String?
    func save(_ token: String, for origin: URL, title: String, api: URL) throws
    func remove(for origin: URL)
    /// Every connected blyg, sorted by title.
    func connections() -> [Connection]
}

nonisolated extension TokenStore {
    func save(_ token: String, for origin: URL) throws {
        try save(token, for: origin, title: origin.host() ?? origin.absoluteString, api: StudioClient.apiBase(forOrigin: origin))
    }
}

nonisolated enum TokenStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// The Keychain, in an access group the Share extension can also read.
nonisolated struct KeychainTokenStore: TokenStore {
    static let service = "net.jdbb.blyg.studio-token"
    /// Must match `keychain-access-groups` in Blyg.entitlements ($(AppIdentifierPrefix) is the team ID plus a dot).
    static let accessGroup = "K24RHPX75P.net.jdbb.blyg.shared"

    private func query(_ origin: URL?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccessGroup as String: Self.accessGroup,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let origin { q[kSecAttrAccount as String] = origin.absoluteString }
        return q
    }

    func token(for origin: URL) -> String? {
        var q = query(origin)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String, for origin: URL, title: String, api: URL) throws {
        let fields: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrLabel as String: title,
            kSecAttrGeneric as String: Data(api.absoluteString.utf8),
        ]
        let update = SecItemUpdate(query(origin) as CFDictionary, fields as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw TokenStoreError.keychain(update) }
        var add = query(origin).merging(fields) { $1 }
        // Readable after the first unlock (so the Share extension works), never synced or restored to another phone.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.keychain(status) }
    }

    func remove(for origin: URL) {
        SecItemDelete(query(origin) as CFDictionary)
    }

    func connections() -> [Connection] {
        var q = query(nil)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { attributes -> Connection? in
            guard let account = attributes[kSecAttrAccount as String] as? String, let origin = URL(string: account) else { return nil }
            let title = (attributes[kSecAttrLabel as String] as? String) ?? origin.host() ?? account
            let api = (attributes[kSecAttrGeneric as String] as? Data).flatMap { URL(string: String(decoding: $0, as: UTF8.self)) }
            return Connection(origin: origin, title: title, api: api ?? StudioClient.apiBase(forOrigin: origin))
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// For tests, UI tests and screenshots: forgets everything when the app quits.
nonisolated final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [URL: (String, Connection)] = [:]

    func token(for origin: URL) -> String? { lock.withLock { tokens[origin]?.0 } }
    func save(_ token: String, for origin: URL, title: String, api: URL) throws {
        lock.withLock { tokens[origin] = (token, Connection(origin: origin, title: title, api: api)) }
    }
    func remove(for origin: URL) { _ = lock.withLock { tokens.removeValue(forKey: origin) } }
    func connections() -> [Connection] {
        lock.withLock { tokens.values.map(\.1) }.sorted { $0.title < $1.title }
    }
}
