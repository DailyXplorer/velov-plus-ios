import Foundation
import Security

public protocol SecureStore: Sendable {
    func read(_ key: String) -> Data?
    func write(_ key: String, _ value: Data) -> Bool
    func delete(_ key: String) -> Bool
}

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

    public func delete(_ key: String) -> Bool {
        [errSecSuccess, errSecItemNotFound].contains(SecItemDelete(query(key) as CFDictionary))
    }
}

public final class InMemoryStore: SecureStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func read(_ key: String) -> Data? { lock.withLock { values[key] } }
    public func write(_ key: String, _ value: Data) -> Bool { lock.withLock { values[key] = value }; return true }
    public func delete(_ key: String) -> Bool { lock.withLock { values[key] = nil }; return true }
}

public enum DeviceIdentity {
    static let key = "device_id"

    public static func stable(in store: SecureStore) -> String {
        if let data = store.read(key), let value = String(data: data, encoding: .utf8), value.wholeMatch(of: /[a-zA-Z0-9-]{16,80}/) != nil {
            return value
        }
        let value = UUID().uuidString.lowercased()
        _ = store.write(key, Data(value.utf8))
        return value
    }
}

public struct StoredSession: Codable, Equatable, Sendable {
    public var tokens: Tokens
    public var accessExpiresAt: Date

    public init(tokens: Tokens, obtainedAt: Date) {
        self.tokens = tokens
        accessExpiresAt = accessExpiry(tokens.accessToken) ?? obtainedAt.addingTimeInterval(tokens.expiresIn)
    }
}

public struct Identity: Sendable {
    public let accessToken: String
    public let email: String
    let live: @Sendable () async -> Bool

    public init(accessToken: String, email: String, live: @escaping @Sendable () async -> Bool = { true }) {
        self.accessToken = accessToken
        self.email = email
        self.live = live
    }
}

@MainActor
public final class SessionGeneration {
    public private(set) var current = 0
    public private(set) var open: Bool
    public init(open: Bool = true) { self.open = open }

    public func begin() {
        current += 1
        open = true
    }

    public func invalidate() {
        current += 1
        open = false
    }

    public func unchanged<T>(_ work: () async -> T) async -> T? {
        let started = current
        let value = await work()
        return started == current ? value : nil
    }

    public func load<T>(_ fetch: () async throws -> T) async -> Result<T, Error>? {
        guard open else { return nil }
        let started = current
        let result: Result<T, Error>
        do { result = .success(try await fetch()) } catch { result = .failure(error) }
        return started == current ? result : nil
    }
}

@MainActor
public final class Forgetter {
    private let send: @Sendable () async -> Bool
    private var pending: Task<Bool, Never>?

    public init(_ send: @escaping @Sendable () async -> Bool) { self.send = send }

    @discardableResult
    public func forget() async -> Bool {
        let previous = pending, send = send
        let task = Task { _ = await previous?.value; return await send() }
        pending = task
        return await task.value
    }

    public func settled() async { _ = await pending?.value }
}

public actor SessionManager {
    static let tokensKey = "tokens"
    private let store: SecureStore
    private let http: HTTPTransport
    private let now: @Sendable () -> Date
    private var session: StoredSession?
    private var refreshing: Task<StoredSession, Error>?
    private var generation = 0

    public init(store: SecureStore, http: HTTPTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.http = http
        self.now = now
        session = store.read(Self.tokensKey).flatMap { try? JSONDecoder().decode(StoredSession.self, from: $0) }
    }

    public var isSignedIn: Bool { session != nil }
    public var email: String? { session.flatMap { try? accountEmail(accessToken: $0.tokens.accessToken) } }
    public var deviceId: String { DeviceIdentity.stable(in: store) }

    public func signIn(email: String, code: String) async throws {
        let started = invalidate()
        let tokens = try await login(email: email, code: code, deviceId: DeviceIdentity.stable(in: store), http: http, now: now())
        guard started == generation else { throw VelovError.sessionRevoked }
        save(StoredSession(tokens: tokens, obtainedAt: now()))
    }

    public func identity() async throws -> Identity {
        guard var current = session else { throw VelovError.sessionRevoked }
        let started = generation
        if current.accessExpiresAt.timeIntervalSince(now()) < 30 { current = try await renew(current) }
        return Identity(accessToken: current.tokens.accessToken, email: try accountEmail(accessToken: current.tokens.accessToken),
                        live: { await self.isCurrent(started) })
    }

    private func isCurrent(_ started: Int) -> Bool { started == generation && session != nil }

    private func renew(_ expired: StoredSession) async throws -> StoredSession {
        let started = generation
        let http = http, now = now
        let task = refreshing ?? Task { StoredSession(tokens: try await refreshTokens(expired.tokens.refreshToken, http: http), obtainedAt: now()) }
        refreshing = task
        defer { if refreshing == task { refreshing = nil } }
        do {
            let renewed = try await task.value
            guard started == generation else { throw VelovError.sessionRevoked }
            if session != renewed { save(renewed) }
            return renewed
        } catch let error as VelovError where error.revoked {
            if started == generation { forget() }
            throw error
        }
    }

    public func logout() async -> Bool {
        let tokens = session?.tokens
        forget()
        return tokens == nil ? true : await endSession(refreshToken: tokens?.refreshToken, idToken: tokens?.idToken, http: http)
    }

    @discardableResult
    public func forget() -> Bool {
        invalidate()
        session = nil
        return store.delete(Self.tokensKey)
    }

    @discardableResult
    private func invalidate() -> Int {
        generation += 1
        refreshing = nil
        return generation
    }

    private func save(_ value: StoredSession) {
        session = value
        if let data = try? JSONEncoder().encode(value) { _ = store.write(Self.tokensKey, data) }
    }
}
