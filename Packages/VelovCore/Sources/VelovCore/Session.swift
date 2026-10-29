import Foundation
import Security

public protocol SecureStore: Sendable {
    func read(_ key: String) -> Data?
    func write(_ key: String, _ value: Data) -> Bool
    func delete(_ key: String)
}

/// Generic passwords in the iOS Keychain, readable after the first unlock, never synced or migrated to another device.
public struct KeychainStore: SecureStore {
    let service: String

    public init(service: String = "io.github.dailyxplorer.velov.session") { self.service = service }

    private func query(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }

    public func read(_ key: String) -> Data? {
        var query = query(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public func write(_ key: String, _ value: Data) -> Bool {
        let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData: value] as CFDictionary)
        if update == errSecSuccess { return true }
        var item = query(key)
        item[kSecValueData] = value
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    public func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}

public final class InMemoryStore: SecureStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func read(_ key: String) -> Data? { lock.withLock { values[key] } }
    public func write(_ key: String, _ value: Data) -> Bool { lock.withLock { values[key] = value }; return true }
    public func delete(_ key: String) { lock.withLock { values[key] = nil } }
}

public enum DeviceIdentity {
    static let key = "device_id"

    /// The id the account is linked with: created once, kept across logouts, never regenerated.
    /// Vélo’v allows one connected device per account, so a new id would look like another phone.
    public static func stable(in store: SecureStore) -> String {
        if let data = store.read(key), let value = String(data: data, encoding: .utf8), value.wholeMatch(of: /[a-zA-Z0-9-]{16,80}/) != nil {
            return value
        }
        let value = UUID().uuidString.lowercased()
        _ = store.write(key, Data(value.utf8))
        return value
    }
}

/// The tokens of the signed-in account, as kept in the Keychain.
public struct StoredSession: Codable, Equatable, Sendable {
    public var tokens: Tokens
    public var accessExpiresAt: Date

    public init(tokens: Tokens, obtainedAt: Date) {
        self.tokens = tokens
        // The token's own exp when readable; expires_in otherwise.
        accessExpiresAt = accessExpiry(tokens.accessToken) ?? obtainedAt.addingTimeInterval(tokens.expiresIn)
    }
}

/// The access token one call needs, and the account it belongs to.
public struct Identity: Sendable {
    public let accessToken: String
    public let email: String
}

/// Keeps the session: Keychain storage, one refresh at a time (a rotated refresh token is spent once), logout.
public actor SessionManager {
    static let tokensKey = "tokens"
    private let store: SecureStore
    private let http: HTTPTransport
    private let now: @Sendable () -> Date
    private var session: StoredSession?
    private var refreshing: Task<StoredSession, Error>?

    public init(store: SecureStore, http: HTTPTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.http = http
        self.now = now
        session = store.read(Self.tokensKey).flatMap { try? JSONDecoder().decode(StoredSession.self, from: $0) }
    }

    public var isSignedIn: Bool { session != nil }
    public var deviceId: String { DeviceIdentity.stable(in: store) }

    /// One login attempt with the stable device id; the tokens go to the Keychain.
    public func signIn(email: String, code: String) async throws {
        let tokens = try await login(email: email, code: code, deviceId: DeviceIdentity.stable(in: store), http: http, now: now())
        save(StoredSession(tokens: tokens, obtainedAt: now()))
    }

    /// A valid access token, renewed first when it expires within 30 s.
    public func identity() async throws -> Identity {
        guard var current = session else { throw VelovError.sessionRevoked }
        if current.accessExpiresAt.timeIntervalSince(now()) < 30 { current = try await renew(current) }
        return Identity(accessToken: current.tokens.accessToken, email: try accountEmail(accessToken: current.tokens.accessToken))
    }

    /// Callers that find the same expired token share one refresh.
    private func renew(_ expired: StoredSession) async throws -> StoredSession {
        if let refreshing { return try await refreshing.value }
        let http = http, now = now
        let task = Task { StoredSession(tokens: try await refreshTokens(expired.tokens.refreshToken, http: http), obtainedAt: now()) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let renewed = try await task.value
            save(renewed)
            return renewed
        } catch let error as VelovError where error.revoked {
            forget()
            throw error
        }
    }

    /// Ends the session at Vélo’v, then forgets the tokens here whatever it answered; the device id stays.
    /// Returns whether Vélo’v confirmed.
    public func logout() async -> Bool {
        let tokens = session?.tokens
        let confirmed = tokens == nil ? true : await endSession(refreshToken: tokens?.refreshToken, idToken: tokens?.idToken, http: http)
        forget()
        return confirmed
    }

    public func forget() {
        session = nil
        store.delete(Self.tokensKey)
    }

    private func save(_ value: StoredSession) {
        session = value
        if let data = try? JSONEncoder().encode(value) { _ = store.write(Self.tokensKey, data) }
    }
}
