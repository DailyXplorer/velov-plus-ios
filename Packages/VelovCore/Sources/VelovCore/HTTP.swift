import Foundation

public enum Cyclocity {
    public static let api = URL(string: "https://api.cyclocity.fr")!
    public static let base = "https://api.cyclocity.fr/contracts/lyon"
    public static let iam = "https://iam.cyclocity.fr"
    public static let realm = "\(iam)/realms/vls-default"
    public static let oidc = "\(realm)/protocol/openid-connect"
    public static let callback = "https://velov.grandlyon.com/openid_connect_login"
    public static let clientId = "vls-web-lyon"
    public static let browserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"
    static let appTokenCode = "vls.web.lyon:PRD"
    static let appTokenKey = "c3d9f5c22a9157a7cc7fe0e38269573bdd2f13ec48f867360ecdcbd35b196f87"
}

public struct VelovError: Error, Equatable, Sendable, LocalizedError {
    public enum Code: String, Sendable { case credentials, refused, expired, unavailable, `protocol`, origin }
    public let code: Code
    public let message: String
    public let revoked: Bool
    public let status: Int?

    public init(_ code: Code, _ message: String, revoked: Bool = false, status: Int? = nil) {
        self.code = code; self.message = message; self.revoked = revoked; self.status = status
    }

    public static let sessionRevoked = VelovError(.expired, Messages.sessionExpired, revoked: true)
    public var errorDescription: String? { message }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public var url: URL?

    public init(status: Int, headers: [String: String] = [:], body: Data = Data(), url: URL? = nil) {
        self.status = status; self.headers = headers; self.body = body; self.url = url
    }

    public var ok: Bool { (200..<300).contains(status) }
    public var text: String { String(decoding: body, as: UTF8.self) }
    public var json: JSON? { JSON.parse(body) }
    public var readable: Bool { body.isEmpty || json != nil }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse
}

extension HTTPTransport {
    public func send(_ request: URLRequest) async throws -> HTTPResponse { try await send(request, followRedirects: true) }
}

private func privateConfiguration(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return configuration
}

private func load(_ request: URLRequest, followRedirects: Bool, on session: URLSession) async throws -> HTTPResponse {
    let observer = TaskObserver(follow: followRedirects && ["GET", "HEAD"].contains((request.httpMethod ?? "GET").uppercased()))
    defer { TechnicalJournal.connection?.line = observer.line }
    let (data, response) = try await session.data(for: request, delegate: observer)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    var headers: [String: String] = [:]
    for (key, value) in http.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
    return HTTPResponse(status: http.statusCode, headers: headers, body: data, url: http.url)
}

public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        session = URLSession(configuration: privateConfiguration(configuration))
    }

    public func send(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse {
        try await load(request, followRedirects: followRedirects, on: session)
    }
}

public final class FreshConnectionTransport: HTTPTransport {
    private let makeSession: @Sendable () -> URLSession

    public convenience init(configuration: URLSessionConfiguration = .ephemeral) {
        nonisolated(unsafe) let configuration = privateConfiguration(configuration)
        self.init { URLSession(configuration: configuration) }
    }

    init(makeSession: @escaping @Sendable () -> URLSession) {
        self.makeSession = makeSession
    }

    public func send(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse {
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }
        return try await load(request, followRedirects: followRedirects, on: session)
    }
}

private final class TaskObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let follow: Bool
    private let lock = NSLock()
    private var metrics: URLSessionTaskTransactionMetrics?

    init(follow: Bool) { self.follow = follow }

    var line: String? {
        guard let metrics = lock.withLock({ metrics }) else { return nil }
        let sent = metrics.countOfRequestHeaderBytesSent + metrics.countOfRequestBodyBytesSent
        return "\(metrics.networkProtocolName ?? "?") · \(metrics.isReusedConnection ? "reused" : "new") connection · sent \(sent) B"
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        follow ? request : nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock { self.metrics = metrics.transactionMetrics.last { $0.resourceFetchType == .networkLoad } ?? metrics.transactionMetrics.last }
    }
}

public func makeRequest(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.httpMethod = method
    request.httpShouldHandleCookies = false
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    if request.value(forHTTPHeaderField: "User-Agent") == nil { request.setValue(Cyclocity.browserAgent, forHTTPHeaderField: "User-Agent") }
    request.httpBody = body
    return request
}

public func formBody(_ fields: [(String, String)]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "*-._")
    let encode = { (value: String) in value.addingPercentEncoding(withAllowedCharacters: allowed)!.replacingOccurrences(of: "%20", with: "+") }
    return Data(fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&").utf8)
}

public func parseForm(_ data: Data) -> [String: String] {
    var fields: [String: String] = [:]
    for pair in String(decoding: data, as: UTF8.self).split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0) }
        fields[parts[0]] = parts.count > 1 ? parts[1] : ""
    }
    return fields
}

func pathSegment(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.!~*'()")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

public struct ReadClient: Sendable {
    public static let attemptTimeout: TimeInterval = 8
    public let transport: HTTPTransport
    let pause: @Sendable (_ seconds: Double) async -> Void

    public init(transport: HTTPTransport, pause: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.transport = transport
        self.pause = pause
    }

    public func fetchTransient(_ request: URLRequest, attempts: Int = 3, before: @Sendable () async throws -> Void = {}) async throws -> HTTPResponse {
        let method = (request.httpMethod ?? "GET").uppercased()
        let url = request.url?.absoluteString ?? ""
        guard method == "GET" || (method == "POST" && url.hasSuffix("/client_tokens")) else {
            throw RefusedRetry(description: "fetchTransient refuses \(method) \(url)")
        }
        var request = request
        request.timeoutInterval = Self.attemptTimeout
        for attempt in 1... {
            try await before()
            let response = try await transport.send(request)
            if attempt >= attempts || ![502, 503, 504].contains(response.status) { return response }
            await pause(Double(attempt) * 0.4)
        }
        fatalError("unreachable")
    }
}

public struct RefusedRetry: Error, CustomStringConvertible {
    public let description: String
}

public actor AppToken {
    private let request: @Sendable () async throws -> String
    private let now: @Sendable () -> Date
    private var current: (token: String, expiresAt: Date)?
    private var pending: Task<String, Error>?

    public init(now: @escaping @Sendable () -> Date = { Date() }, request: @escaping @Sendable () async throws -> String) {
        self.request = request
        self.now = now
    }

    public func get() async throws -> String {
        if let current, current.expiresAt > now() { return current.token }
        if let pending { return try await pending.value }
        let task = Task { try await request() }
        pending = task
        defer { if pending == task { pending = nil } }
        let token = try await task.value
        current = (token, now().addingTimeInterval(100 * 60))
        return token
    }

    public func drop(_ token: String) {
        if current?.token == token { current = nil }
    }
}

public func getWithAppToken(_ client: ReadClient, _ tokens: AppToken, _ url: URL, before: @Sendable () async throws -> Void = {},
                            headers: @Sendable (String) -> [String: String]) async throws -> HTTPResponse {
    for attempt in 1... {
        let token = try await tokens.get()
        let response = try await client.fetchTransient(makeRequest(url, headers: headers(token), timeout: ReadClient.attemptTimeout), before: before)
        if response.status != 401 || attempt > 1 { return response }
        await tokens.drop(token)
    }
    fatalError("unreachable")
}

public actor Memo<Value: Sendable> {
    private let ttl: @Sendable (Value) -> TimeInterval
    private let stale: Bool
    private let now: @Sendable () -> Date
    private var values: [String: (value: Value, expiresAt: Date)] = [:]
    private var pending: [String: (generation: Int, task: Task<Value, Error>)] = [:]
    private var generation = 0

    public init(ttl: TimeInterval, stale: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(ttl: { _ in ttl }, stale: stale, now: now)
    }

    public init(ttl: @escaping @Sendable (Value) -> TimeInterval, stale: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl; self.stale = stale; self.now = now
    }

    public func get(_ key: String, _ load: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let hit = values[key], hit.expiresAt > now() { return hit.value }
        if let running = pending[key], running.generation == generation {
            do { return try await running.task.value } catch {
                if stale, let last = values[key] { return last.value }
                throw error
            }
        }
        let started = generation
        let task = Task { try await load() }
        pending[key] = (started, task)
        defer { if pending[key]?.task == task { pending[key] = nil } }
        do {
            let value = try await task.value
            if started == generation { values[key] = (value, now().addingTimeInterval(ttl(value))) }
            return value
        } catch {
            if stale, let last = values[key] { return last.value }
            throw error
        }
    }

    public func clear() {
        values = [:]
        pending = [:]
        generation += 1
    }
}
