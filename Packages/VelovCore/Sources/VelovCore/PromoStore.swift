import CryptoKit
import Foundation

// Invitation codes obtained for points, kept on the phone (the web client's `lib/promo-storage.ts`).
// The code is the only proof of a debit: the store must be writable before the debit and is written before anything else after it.

/// Where the codes live: one text value per key. Both calls may fail; a failure is never hidden.
public protocol PromoBacking: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ key: String, _ value: String) throws
}

/// One file per key in `directory`, written atomically.
public struct FilePromoBacking: PromoBacking {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    private func file(_ key: String) -> URL {
        directory.appendingPathComponent(key.replacingOccurrences(of: ":", with: "_") + ".json")
    }

    public func read(_ key: String) throws -> String? {
        let url = file(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    public func write(_ key: String, _ value: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(value.utf8).write(to: file(key), options: .atomic)
    }
}

/// For tests and previews; `failWrites` makes every write throw.
public final class InMemoryPromoBacking: PromoBacking, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var failing: Bool

    public init(_ values: [String: String] = [:], failWrites: Bool = false) { self.values = values; failing = failWrites }

    public var failWrites: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    public func value(_ key: String) -> String? { lock.withLock { values[key] } }
    public func read(_ key: String) throws -> String? { lock.withLock { values[key] } }

    public func write(_ key: String, _ value: String) throws {
        try lock.withLock {
            if failing { throw CocoaError(.fileWriteNoPermission) }
            values[key] = value
        }
    }
}

public struct SavedPromo: Codable, Equatable, Sendable {
    public var code: String
    public var createdAt: String
    public init(code: String, createdAt: String) { self.code = code; self.createdAt = createdAt }
}

public enum PromoStore {
    /// No account address is stored in the key. Codes remain local to this phone and account.
    public static func key(account: String) -> String {
        let digest = SHA256.hash(data: Data(account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8))
        return "velov:promocodes:v1:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Throws on unreadable storage. Do not overwrite corrupt storage: an older code may still be recoverable there.
    public static func read(_ backing: PromoBacking, key: String) throws -> [SavedPromo] {
        guard let raw = try backing.read(key) else { return [] }
        let codes = try JSONDecoder().decode([SavedPromo].self, from: Data(raw.utf8))
        guard codes.allSatisfy({ !$0.code.isEmpty }) else { throw CocoaError(.coderInvalidValue) }
        return codes
    }

    /// Proves the storage readable and writable before any debit.
    @discardableResult
    public static func prepare(_ backing: PromoBacking, key: String) throws -> [SavedPromo] {
        let codes = try read(backing, key: key)
        try backing.write(key, encode(codes))
        return codes
    }

    @discardableResult
    public static func save(_ backing: PromoBacking, key: String, code: String, now: Date = Date()) throws -> [SavedPromo] {
        let current = try read(backing, key: key)
        let next = current.contains { $0.code == code } ? current : current + [SavedPromo(code: code, createdAt: isoString(now))]
        try backing.write(key, encode(next))
        return next
    }

    private static func encode(_ codes: [SavedPromo]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(codes), as: UTF8.self)
    }

    /// `Date.toISOString()`: UTC with milliseconds.
    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
