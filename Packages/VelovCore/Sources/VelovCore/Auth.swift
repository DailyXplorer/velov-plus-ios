import CryptoKit
import Foundation

public struct Tokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var idToken: String
    /// Seconds.
    public var expiresIn: Double
    /// Seconds; Keycloak sends 0 for a refresh token without its own expiry.
    public var refreshExpiresIn: Double

    public init(accessToken: String, refreshToken: String, idToken: String, expiresIn: Double, refreshExpiresIn: Double) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.idToken = idToken
        self.expiresIn = expiresIn; self.refreshExpiresIn = refreshExpiresIn
    }

    /// The token endpoint's answer, every field checked.
    static func parse(_ value: JSON?) throws -> Tokens {
        guard let value, let access = value["access_token"]?.string, !access.isEmpty, let refresh = value["refresh_token"]?.string, !refresh.isEmpty,
              let identity = value["id_token"]?.string, !identity.isEmpty, let expires = value["expires_in"]?.number, expires > 0,
              let refreshExpires = value["refresh_expires_in"]?.number, refreshExpires >= 0 else {
            throw VelovError(.unavailable, "La session n’a pas pu être ouverte. Réessayez.")
        }
        return Tokens(accessToken: access, refreshToken: refresh, idToken: identity, expiresIn: expires, refreshExpiresIn: refreshExpires)
    }
}

public struct Authorization: Sendable {
    public let state: String
    public let nonce: String
    public let verifier: String
    public let url: URL
}

private func randomToken(_ count: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: count)
    precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess)
    return base64URL(Data(bytes))
}

/// The PKCE S256 challenge of a verifier.
public func codeChallenge(_ verifier: String) -> String {
    base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
}

public func makeAuthorization() -> Authorization {
    let state = randomToken(24), nonce = randomToken(24), verifier = randomToken(48)
    var components = URLComponents(string: "\(Cyclocity.oidc)/auth")!
    components.queryItems = [
        ("client_id", Cyclocity.clientId), ("response_type", "code"), ("scope", "openid email"), ("ui_locales", "fr"),
        ("redirect_uri", Cyclocity.callback), ("code_challenge", codeChallenge(verifier)), ("code_challenge_method", "S256"),
        ("state", state), ("nonce", nonce)
    ].map { URLQueryItem(name: $0.0, value: $0.1) }
    return Authorization(state: state, nonce: nonce, verifier: verifier, url: components.url!)
}

private func isCallback(_ url: URL) -> Bool {
    let callback = URL(string: Cyclocity.callback)!
    return url.scheme == callback.scheme && url.host == callback.host && url.port == callback.port && url.path == callback.path
}

/// The authorization code of the expected callback for this login.
public func readCallback(_ value: String, state: String) throws -> String {
    guard let url = URL(string: value), isCallback(url), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
          items.first(where: { $0.name == "state" })?.value == state, !items.contains(where: { $0.name == "error" }),
          let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
        throw VelovError(.protocol, "Le retour de connexion n’a pas pu être vérifié.")
    }
    return code
}

/// The Keycloak pages of one login: their own cookie jar, redirects followed by hand, never outside the realm.
final class LoginTransport {
    enum Page { case page(String), callback(String) }
    private var cookies: [(String, String)] = []
    private let http: HTTPTransport

    init(_ http: HTTPTransport) { self.http = http }

    func request(_ start: URL, fields: [(String, String)]? = nil) async throws -> Page {
        var url = start
        var fields = fields
        for _ in 0..<10 {
            url = try safeIAMURL(url.absoluteString)
            var headers = ["Accept-Language": "fr"]
            if !cookies.isEmpty { headers["Cookie"] = cookies.map { "\($0.0)=\($0.1)" }.joined(separator: "; ") }
            if fields != nil { headers["Content-Type"] = "application/x-www-form-urlencoded" }
            let request = makeRequest(url, method: fields == nil ? "GET" : "POST", headers: headers, body: fields.map(formBody), timeout: 20)
            let response = try await http.send(request, followRedirects: false)
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: response.headers, for: url) {
                if let index = cookies.firstIndex(where: { $0.0 == cookie.name }) { cookies[index].1 = cookie.value } else { cookies.append((cookie.name, cookie.value)) }
            }
            if [301, 302, 303].contains(response.status) {
                guard let location = response.header("Location"), let next = URL(string: location, relativeTo: url)?.absoluteURL else {
                    throw VelovError(.protocol, "Le serveur de connexion n’a pas répondu comme prévu.")
                }
                if isCallback(next) { return .callback(next.absoluteString) }
                url = try safeIAMURL(next.absoluteString)
                fields = nil
                continue
            }
            let html = response.text
            if !response.ok {
                if (400..<500).contains(response.status) { throw VelovError(.refused, serverRefusal(html) ?? Messages.loginRefused) }
                throw VelovError(.unavailable, "Vélo’v ne peut pas vous connecter pour le moment. Réessayez dans un instant.")
            }
            return .page(html)
        }
        throw VelovError(.protocol, "La connexion n’a pas pu se terminer.")
    }
}

/// Headless Keycloak login: credentials form, then the device form with the phone's stable device id, then the code exchange.
/// Exactly one pass: a refusal is shown, never retried.
public func login(email: String, code: String, deviceId: String, http: HTTPTransport, now: Date = Date()) async throws -> Tokens {
    let authorization = makeAuthorization()
    let transport = LoginTransport(http)
    guard case .page(let first) = try await transport.request(authorization.url) else {
        throw VelovError(.protocol, "Un nouveau formulaire de connexion est nécessaire.")
    }
    var form = try readForm(first, id: "kc-form-login")
    form.set("username", email)
    form.set("password", code)
    form.set("credentialId", "")
    var response = try await transport.request(form.url, fields: form.fields)
    if case .page(let html) = response {
        var device = try readForm(html, id: "vls-form-device-id")
        device.set("device_id", deviceId)
        response = try await transport.request(device.url, fields: device.fields)
    }
    guard case .callback(let callback) = response else { throw VelovError(.protocol, "La connexion n’a pas pu se terminer.") }
    let authorizationCode = try readCallback(callback, state: authorization.state)
    let exchange = makeRequest(URL(string: "\(Cyclocity.oidc)/token")!, method: "POST", headers: ["Content-Type": "application/x-www-form-urlencoded"],
                               body: formBody([("grant_type", "authorization_code"), ("client_id", Cyclocity.clientId), ("redirect_uri", Cyclocity.callback),
                                               ("code", authorizationCode), ("code_verifier", authorization.verifier)]), timeout: 20)
    let answer = try await http.send(exchange, followRedirects: false)
    guard answer.ok else { throw VelovError(.unavailable, "La session n’a pas pu être ouverte. Réessayez.") }
    let tokens = try Tokens.parse(answer.json)
    let certs = try await http.send(makeRequest(URL(string: "\(Cyclocity.oidc)/certs")!, timeout: 20), followRedirects: false)
    try verifyIdentity(tokens.idToken, jwks: certs.json, nonce: authorization.nonce, now: now)
    return tokens
}

/// The id token: signed by the realm, for this client, this login, still valid.
func verifyIdentity(_ token: String, jwks: JSON?, nonce: String, now: Date) throws {
    let failed = VelovError(.protocol, "La réponse de connexion n’a pas pu être vérifiée.")
    guard let jwt = JWT(token), let jwks, jwt.verifiesRS256(jwks: jwks) else { throw failed }
    let audience = jwt.payload["aud"]
    let audiences = audience?.array?.compactMap(\.string) ?? audience?.string.map { [$0] } ?? []
    guard jwt.payload["iss"]?.string == Cyclocity.realm, audiences.contains(Cyclocity.clientId), jwt.payload["nonce"]?.string == nonce,
          let expiry = jwt.payload["exp"]?.number, expiry > now.timeIntervalSince1970 else { throw failed }
}

/// Renews the session with its refresh token, never a password. Only a refusal of the token itself ends the session.
public func refreshTokens(_ refreshToken: String, http: HTTPTransport) async throws -> Tokens {
    let request = makeRequest(URL(string: "\(Cyclocity.oidc)/token")!, method: "POST", headers: ["Content-Type": "application/x-www-form-urlencoded"],
                              body: formBody([("grant_type", "refresh_token"), ("client_id", Cyclocity.clientId), ("refresh_token", refreshToken)]), timeout: 20)
    let response = try await http.send(request, followRedirects: false)
    if [400, 401].contains(response.status) { throw VelovError.sessionRevoked }
    guard response.ok else { throw VelovError(.unavailable, "Vélo’v est momentanément indisponible.") }
    return try Tokens.parse(response.json)
}

/// Ends the session at the identity provider; true only when it confirmed. The refresh token is preferred, the id token is the fallback.
public func endSession(refreshToken: String?, idToken: String?, http: HTTPTransport) async -> Bool {
    do {
        if let refreshToken {
            let request = makeRequest(URL(string: "\(Cyclocity.oidc)/logout")!, method: "POST", headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                      body: formBody([("client_id", Cyclocity.clientId), ("refresh_token", refreshToken)]), timeout: 10)
            return try await http.send(request, followRedirects: false).ok
        }
        guard let idToken else { return true }
        var components = URLComponents(string: "\(Cyclocity.oidc)/logout")!
        components.queryItems = [URLQueryItem(name: "id_token_hint", value: idToken), URLQueryItem(name: "post_logout_redirect_uri", value: "https://velov.grandlyon.com/openid_connect_logout")]
        let response = try await http.send(makeRequest(components.url!, timeout: 10), followRedirects: false)
        // Keycloak answers this one with a redirect to post_logout_redirect_uri.
        return response.ok || [302, 303].contains(response.status)
    } catch {
        return false
    }
}

/// The account e-mail an access token was issued for, to this client.
public func accountEmail(accessToken: String) throws -> String {
    guard let jwt = JWT(accessToken) else { throw VelovError(.expired, "Cette session doit être renouvelée.") }
    guard jwt.payload["azp"]?.string == Cyclocity.clientId else { throw VelovError(.expired, "Cette session doit être renouvelée.") }
    let email = jwt.payload["preferred_username"]?.string ?? jwt.payload["sub"]?.string ?? ""
    guard email.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil else {
        throw VelovError(.protocol, "Le compte associé à cette session n’a pas pu être vérifié.")
    }
    return email
}

public func accessExpiry(_ accessToken: String) -> Date? {
    JWT(accessToken)?.payload["exp"]?.number.map(Date.init(timeIntervalSince1970:))
}
