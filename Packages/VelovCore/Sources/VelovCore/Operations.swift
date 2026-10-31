import CryptoKit
import Foundation
import Observation

public func accountDigest(_ account: String) -> String {
    SHA256.hash(data: Data(account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
}

public func noAnswer(_ message: String) -> Outcome {
    Outcome(ok: false, httpStatus: 0, code: "network", message: message)
}

public protocol OperationBacking: AnyObject {
    func read(_ key: String) throws -> Data?
    func write(_ key: String, _ value: Data?) throws
    func keys() throws -> [String]
}

public final class DefaultsOperationBacking: OperationBacking {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func read(_ key: String) -> Data? { defaults.data(forKey: key) }
    public func write(_ key: String, _ value: Data?) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    public func keys() -> [String] { Array(defaults.dictionaryRepresentation().keys) }
}

public final class InMemoryOperationBacking: OperationBacking {
    public var values: [String: Data] = [:]
    public var failing: Bool
    public init(failing: Bool = false) { self.failing = failing }
    public func read(_ key: String) throws -> Data? {
        if failing { throw CocoaError(.fileReadNoPermission) }
        return values[key]
    }
    public func write(_ key: String, _ value: Data?) throws {
        if failing { throw CocoaError(.fileWriteNoPermission) }
        values[key] = value
    }
    public func keys() throws -> [String] {
        if failing { throw CocoaError(.fileReadNoPermission) }
        return Array(values.keys)
    }
}

public enum OperationKey {
    public static func unlock(_ bike: Int) -> String { "unlock:\(bike)" }
    public static func book(_ bike: Int) -> String { "book:\(bike)" }
    public static func invite(_ digest: String) -> String { "invite:\(digest)" }
    public static func contact(_ digest: String) -> String { "contact:\(digest)" }
    public static func via(_ digest: String, tripId: String) -> String { "via:\(digest):\(tripId)" }
    public static func rate(_ tripId: String) -> String { "rate:\(tripId)" }
    public static func favorite(_ station: Int) -> String { "favorite:\(station)" }
    public static func autoRenewal(_ subscriptionId: String) -> String { "autoRenewal:\(subscriptionId)" }
    public static let profile = "profile"
    public static let autoSpend = "autoSpend"
}

@MainActor
@Observable
public final class Operations {
    public static let storageKey = "velov:operations:v1"

    public struct Entry: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable { case sending, uncertain }
        public var status: Status
        public var at: Date
        public var outcome: Outcome?
        public var meta: [String: String]

        var scrubbed: Entry {
            var entry = self
            entry.meta = scrubbedIntent(meta)
            return entry
        }
    }

    public enum Began: Equatable, Sendable { case started, busy, unsaved }
    public enum Run: Equatable, Sendable { case busy, unsaved, superseded, finished(Outcome) }

    @ObservationIgnored private let backing: OperationBacking?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let session: SessionGeneration?
    @ObservationIgnored private var running: [String: String] = [:]
    @ObservationIgnored private var memory: [String: Entry] = [:]
    public private(set) var digest: String?
    public private(set) var version = 0

    public init(backing: OperationBacking?, account: String? = nil, session: SessionGeneration? = nil, now: @escaping () -> Date = Date.init) {
        self.backing = backing
        self.now = now
        self.session = session
        digest = account.map(accountDigest)
        scrubStored()
    }

    private func scrubStored() {
        guard let backing, let keys = try? backing.keys() else { return }
        for key in keys where key.hasPrefix("\(Self.storageKey):") {
            guard let raw = try? backing.read(key), let all = try? JSONDecoder().decode([String: Entry].self, from: raw) else { continue }
            let clean = all.mapValues(\.scrubbed)
            if clean != all { try? backing.write(key, try JSONEncoder().encode(clean)) }
        }
    }

    public func use(account: String?) {
        let next = account.map(accountDigest)
        guard next != digest else { return }
        digest = next
        memory = [:]
        changed()
    }

    private func saved(_ owner: String? = nil) -> [String: Entry]? {
        guard let backing, let owner = owner ?? digest else { return nil }
        do {
            guard let raw = try backing.read("\(Self.storageKey):\(owner)") else { return [:] }
            return try JSONDecoder().decode([String: Entry].self, from: raw).mapValues(\.scrubbed)
        } catch {
            return nil
        }
    }

    private func live(_ key: String, _ entry: Entry?) -> Entry? {
        guard var entry, entry.status == .sending, running[key] == nil else { return entry }
        entry.status = .uncertain
        entry.outcome = entry.outcome ?? noAnswer(Messages.lost)
        return entry
    }

    private func changed() { version += 1 }

    private func write(_ key: String, _ entry: Entry?, required: Bool, owner: String? = nil) throws {
        let owner = owner ?? digest
        let current = owner == digest
        let previous = memory[key]
        if current { memory[key] = entry }
        do {
            guard let backing, let owner, var all = saved(owner) else { throw CocoaError(.fileWriteUnknown) }
            all[key] = entry
            try backing.write("\(Self.storageKey):\(owner)", all.isEmpty ? nil : try JSONEncoder().encode(all))
        } catch {
            guard required else { return }
            if current { memory[key] = previous }
            throw error
        }
    }

    public func get(_ key: String) -> Entry? {
        _ = version
        let all = saved()
        let entry = live(key, all.map { $0[key] } ?? memory[key])
        if running[key] != nil && entry?.status != .sending {
            return Entry(status: .sending, at: now(), outcome: nil, meta: [:])
        }
        return entry
    }

    public func busy() -> Bool { sending }

    public var sending: Bool {
        _ = version
        return !running.isEmpty
    }

    public func begin(_ key: String, meta: [String: String] = [:]) -> Began {
        if busy() || get(key) != nil { return .busy }
        guard let owner = digest else { return .unsaved }
        do { try write(key, Entry(status: .sending, at: now(), outcome: nil, meta: meta), required: true) } catch { return .unsaved }
        running[key] = owner
        changed()
        return .started
    }

    public func finish(_ key: String, _ outcome: Outcome) {
        let owner = running.removeValue(forKey: key) ?? digest
        let entry = (owner == digest ? memory[key] : nil) ?? saved(owner)?[key]
        let next = outcome.ok || !outcome.isUncertain ? nil : Entry(status: .uncertain, at: now(), outcome: outcome, meta: entry?.meta ?? [:])
        try? write(key, next, required: false, owner: owner)
        changed()
    }

    public func clear(_ key: String) {
        guard running[key] == nil else { return }
        try? write(key, nil, required: false)
        changed()
    }

    public func clear(_ key: String, held: Entry) {
        guard get(key)?.at == held.at else { return }
        clear(key)
    }

    public func settleHeld(_ key: String, check: ([String: String]) async throws -> Check) async -> Settled? {
        guard let held = get(key), held.status == .uncertain else { return nil }
        let started = session?.current
        let settled = await settle(held.outcome ?? noAnswer(Messages.lost), at: held.at, now: now) { try await check(held.meta) }
        guard started == session?.current else { return nil }
        if case .uncertain = settled { return settled }
        clear(key, held: held)
        return settled
    }

    public func runOnce(_ key: String, meta: [String: String] = [:], _ send: () async throws -> Outcome) async -> Run {
        switch begin(key, meta: meta) {
        case .busy: return .busy
        case .unsaved: return .unsaved
        case .started: break
        }
        let started = session?.current
        let outcome: Outcome
        do { outcome = try await TechnicalJournal.$operation.withValue(key) { try await send() } } catch {
            var lost = noAnswer(Messages.noReply)
            lost.detail = networkLine(error)
            outcome = lost
        }
        finish(key, outcome)
        return started == session?.current ? .finished(outcome) : .superseded
    }
}
