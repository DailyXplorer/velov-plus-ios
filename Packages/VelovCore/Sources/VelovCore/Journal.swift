import Foundation

private let urlErrorNames: [Int: String] = [
    -1: "Unknown", -999: "Cancelled", -1000: "BadURL", -1001: "TimedOut", -1002: "UnsupportedURL", -1003: "CannotFindHost",
    -1004: "CannotConnectToHost", -1005: "NetworkConnectionLost", -1006: "DNSLookupFailed", -1007: "HTTPTooManyRedirects",
    -1008: "ResourceUnavailable", -1009: "NotConnectedToInternet", -1010: "RedirectToNonExistentLocation", -1011: "BadServerResponse",
    -1012: "UserCancelledAuthentication", -1013: "UserAuthenticationRequired", -1014: "ZeroByteResource", -1015: "CannotDecodeRawData",
    -1016: "CannotDecodeContentData", -1017: "CannotParseResponse", -1018: "InternationalRoamingOff", -1019: "CallIsActive",
    -1020: "DataNotAllowed", -1021: "RequestBodyStreamExhausted", -1022: "AppTransportSecurityRequiresSecureConnection",
    -1103: "DataLengthExceedsMaximum", -1200: "SecureConnectionFailed", -1201: "ServerCertificateHasBadDate",
    -1202: "ServerCertificateUntrusted", -1203: "ServerCertificateHasUnknownRoot", -1204: "ServerCertificateNotYetValid",
    -1205: "ClientCertificateRejected", -1206: "ClientCertificateRequired", -2000: "CannotLoadFromNetwork"
]

private let urlErrorLabels: [Int: String] = [
    -999: "Requête annulée", -1001: "Délai dépassé", -1003: "Serveur introuvable", -1004: "Connexion impossible",
    -1005: "Connexion perdue", -1006: "Serveur introuvable", -1009: "Pas de réseau", -1011: "Réponse invalide",
    -1017: "Réponse illisible", -1018: "Itinérance désactivée", -1020: "Données cellulaires désactivées",
    -1200: "Connexion sécurisée impossible", -1202: "Certificat refusé"
]

public func urlErrorName(_ code: Int) -> String {
    urlErrorNames[code].map { "NSURLError\($0)" } ?? "NSURLErrorDomain"
}

func formatSeconds(_ seconds: TimeInterval) -> String {
    "\(formatNumber(seconds, maximumFractionDigits: seconds < 10 ? 1 : 0))\u{a0}s"
}

public struct NetworkFailure: Error, Equatable, Sendable, LocalizedError {
    public let code: Int
    public let elapsed: TimeInterval?

    public init(code: Int, elapsed: TimeInterval?) { self.code = code; self.elapsed = elapsed }

    public var line: String {
        let label = urlErrorLabels[code] ?? "Erreur réseau"
        let after = elapsed.map { " après \(formatSeconds($0))" } ?? ""
        return "\(label)\(after) · \(urlErrorName(code)) (\(code))"
    }

    public var errorDescription: String? { line }
}

public func networkLine(_ error: Error) -> String {
    if let failure = error as? NetworkFailure { return failure.line }
    if let error = error as? URLError { return NetworkFailure(code: error.code.rawValue, elapsed: nil).line }
    return "Erreur réseau · \(String(describing: type(of: error)))"
}

public struct JournalEntry: Codable, Equatable, Sendable {
    public var at: Date
    public var method: String
    public var path: String
    public var status: Int?
    public var error: Int?
    public var duration: TimeInterval
    public var operation: String?
    public var connection: String?

    var isWrite: Bool { method != "GET" || operation != nil }

    public var result: String {
        if let status { return "HTTP \(status)" }
        return "\(urlErrorName(error ?? -1)) (\(error ?? -1))"
    }

    public var milliseconds: String { "\(formatNumber(Int((duration * 1000).rounded())))\u{a0}ms" }
}

private let keptQueries: Set<String> = ["stationNumber", "number", "page", "size", "status", "periods", "typeList", "sort", "isLocked"]

private func kept(_ segment: String) -> Bool {
    if segment.count <= 3 && segment.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return true }
    if segment.count <= 6 && segment.allSatisfy({ $0.isASCII && $0.isNumber }) { return true }
    return segment.wholeMatch(of: /[A-Za-z_.,\-]+/) != nil
}

public func redactedPath(_ url: URL) -> String {
    let path = url.path.split(separator: "/", omittingEmptySubsequences: false).map { kept(String($0)) ? String($0) : "•" }.joined(separator: "/")
    guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty else { return path }
    let query = items.map { item in
        let value = item.value ?? ""
        return "\(kept(item.name) ? item.name : "•")=\(keptQueries.contains(item.name) && kept(value) ? value : "•")"
    }
    return "\(path)?\(query.joined(separator: "&"))"
}

public func redactedOperation(_ key: String) -> String {
    let parts = key.split(separator: ":").map(String.init)
    guard let head = parts.first, kept(head) else { return "•" }
    return ([head] + parts.dropFirst().filter { $0.count <= 6 && $0.allSatisfy { $0.isASCII && $0.isNumber } }).joined(separator: ":")
}

public final class TechnicalJournal: @unchecked Sendable {
    public static let capacity = 50
    public static let writeCapacity = 100
    public static let writeRetention: TimeInterval = 14 * 24 * 3600
    public static let shared = TechnicalJournal()
    @TaskLocal public static var operation: String?
    @TaskLocal static var connection: ConnectionNote?

    private let defaults: UserDefaults
    private let key: String
    private let writesKey: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "velov:journal:v1") {
        self.defaults = defaults
        self.key = key
        writesKey = "\(key):writes"
    }

    private func stored(_ key: String) -> [JournalEntry] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([JournalEntry].self, from: $0) } ?? []
    }

    public var entries: [JournalEntry] { lock.withLock { (stored(key) + stored(writesKey)).sorted { $0.at > $1.at } } }

    public func record(_ request: URLRequest, status: Int?, error: Int?, duration: TimeInterval, at: Date, connection: String? = nil) {
        guard let url = request.url, url.host?.hasSuffix("cyclocity.fr") == true else { return }
        let entry = JournalEntry(at: at, method: (request.httpMethod ?? "GET").uppercased(), path: redactedPath(url), status: status,
                                 error: status == nil ? error ?? -1 : nil, duration: max(0, duration), operation: Self.operation.map(redactedOperation),
                                 connection: connection)
        lock.withLock {
            let ring = entry.isWrite ? writesKey : key
            var next = [entry] + stored(ring)
            if entry.isWrite { next = next.filter { at.timeIntervalSince($0.at) < Self.writeRetention } }
            defaults.set(try? JSONEncoder().encode(Array(next.prefix(entry.isWrite ? Self.writeCapacity : Self.capacity))), forKey: ring)
        }
    }

    public func clear() {
        lock.withLock {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: writesKey)
        }
    }

    public func export(timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let lines = entries.map { entry in
            ([formatter.string(from: entry.at), "\(entry.method) \(entry.path)", entry.result, entry.milliseconds] + [entry.operation, entry.connection].compactMap { $0 })
                .joined(separator: " · ")
        }
        return (["Journal technique Vélo’v+"] + lines).joined(separator: "\n")
    }
}

final class ConnectionNote: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    var line: String? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

public struct JournalTransport: HTTPTransport {
    let base: HTTPTransport
    let journal: TechnicalJournal
    let clock: @Sendable () -> Date

    public init(_ base: HTTPTransport, journal: TechnicalJournal = .shared, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.base = base
        self.journal = journal
        self.clock = clock
    }

    public func send(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse {
        let start = clock()
        let note = ConnectionNote()
        do {
            let response = try await TechnicalJournal.$connection.withValue(note) { try await base.send(request, followRedirects: followRedirects) }
            journal.record(request, status: response.status, error: nil, duration: clock().timeIntervalSince(start), at: start, connection: note.line)
            return response
        } catch {
            let elapsed = clock().timeIntervalSince(start)
            let code = (error as? URLError)?.code.rawValue
            journal.record(request, status: nil, error: code ?? -1, duration: elapsed, at: start, connection: note.line)
            guard let code else { throw error }
            throw NetworkFailure(code: code, elapsed: elapsed)
        }
    }
}
