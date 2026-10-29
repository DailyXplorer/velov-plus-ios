import Foundation
@testable import VelovCore

/// What a mocked endpoint answers.
enum Reply {
    case status(Int, body: String = "", headers: [String: String] = [:])
    case json(Any, status: Int = 200, headers: [String: String] = [:])
    case failure(URLError.Code)
}

struct Call {
    let request: URLRequest
    let body: Data
    var url: String { request.url!.absoluteString }
    var method: String { request.httpMethod ?? "GET" }
    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    var bodyText: String { String(decoding: body, as: UTF8.self) }
}

/// A URLProtocol-backed fake of Cyclocity: every request of the session it configures lands in `handler`, nothing reaches the network.
final class MockServer: @unchecked Sendable {
    private static var servers: [String: MockServer] = [:]
    private static let lock = NSLock()
    fileprivate static func server(for request: URLRequest) -> MockServer? {
        guard let id = request.value(forHTTPHeaderField: "X-Mock-Server") else { return nil }
        return lock.withLock { servers[id] }
    }

    let id = UUID().uuidString
    private let lock = NSLock()
    private var recorded: [Call] = []
    var handler: @Sendable (Call, Int) async -> Reply

    init(_ handler: @escaping @Sendable (Call, Int) async -> Reply = { _, _ in .status(500) }) {
        self.handler = handler
        Self.lock.withLock { Self.servers[id] = self }
    }

    var calls: [Call] { lock.withLock { recorded } }
    func reset() { lock.withLock { recorded = [] } }

    fileprivate func record(_ call: Call) -> Int {
        lock.withLock { recorded.append(call); return recorded.count - 1 }
    }

    /// A transport whose every request is answered here.
    var transport: URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Mock-Server": id]
        return URLSessionTransport(configuration: configuration)
    }
}

final class MockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let server = MockServer.server(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        let call = Call(request: request, body: body)
        let index = server.record(call)
        let request = request
        Task {
            let reply = await server.handler(call, index)
            let (status, data, headers): (Int, Data, [String: String])
            switch reply {
            case .failure(let code):
                self.client?.urlProtocol(self, didFailWithError: URLError(code))
                return
            case .status(let code, let text, let extra):
                (status, data, headers) = (code, Data(text.utf8), extra)
            case .json(let value, let code, let extra):
                let encoded = try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
                (status, data, headers) = (code, encoded, ["Content-Type": "application/json"].merging(extra) { $1 })
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
}

let noPause: @Sendable (Double) async -> Void = { _ in }

func date(_ value: String) -> Date { cyclocityDate(value)! }
