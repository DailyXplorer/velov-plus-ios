import CryptoKit
import Security
import XCTest
@testable import VelovCore

/// A throwaway RSA key standing in for the realm's signing key.
struct TestSigner {
    let privateKey: SecKey
    let jwks: [String: Any]

    init() {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil)!
        let der = SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(privateKey)!, nil)! as Data
        let (modulus, exponent) = Self.integers(der)
        jwks = ["keys": [["kty": "RSA", "kid": "test", "alg": "RS256", "use": "sig", "n": base64URL(modulus), "e": base64URL(exponent)]]]
    }

    /// The two INTEGERs of a PKCS#1 RSAPublicKey.
    static func integers(_ der: Data) -> (Data, Data) {
        var bytes = [UInt8](der)
        func length() -> Int {
            let first = Int(bytes.removeFirst())
            if first < 0x80 { return first }
            var value = 0
            for _ in 0..<(first & 0x7f) { value = value << 8 | Int(bytes.removeFirst()) }
            return value
        }
        bytes.removeFirst(); _ = length()
        bytes.removeFirst(); let modulusLength = length()
        let modulus = Data(bytes.prefix(modulusLength)); bytes.removeFirst(modulusLength)
        bytes.removeFirst(); let exponentLength = length()
        return (modulus, Data(bytes.prefix(exponentLength)))
    }

    func sign(_ payload: [String: Any], kid: String = "test") -> String {
        let header = base64URL(try! JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT", "kid": kid]))
        let body = base64URL(try! JSONSerialization.data(withJSONObject: payload))
        let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data("\(header).\(body)".utf8) as CFData, nil)! as Data
        return "\(header).\(body).\(base64URL(signature))"
    }
}

/// An unsigned access token: the app only reads it, Cyclocity checks it.
func accessToken(email: String = "person@example.com", expires: Date) -> String {
    let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
    let payload = base64URL(try! JSONSerialization.data(withJSONObject: ["azp": "vls-ios-lyon", "preferred_username": email, "exp": expires.timeIntervalSince1970]))
    return "\(header).\(payload).sig"
}

func query(_ url: String, _ name: String) -> String? {
    URLComponents(string: url)?.queryItems?.first { $0.name == name }?.value
}

let loginPage = """
<html><body><form id="kc-form-login" action="/realms/vls-default/login-actions/authenticate?session_code=abc&amp;execution=e1&amp;client_id=vls-ios-lyon" method="post">
<input type="hidden" name="session" value="preserved"/><input name="username"/><input type="password" name="password"/></form></body></html>
"""
let devicePage = """
<html><form id='vls-form-device-id' action='https://iam.cyclocity.fr/realms/vls-default/login-actions/required-action?execution=device'>
<input type=hidden name=device_id value=''><input type="HIDDEN" name="tab_id" value="t-1"></form></html>
"""

final class AuthTests: XCTestCase {
    func testALoginStartsWithAUniqueStateNonceAndS256Proof() {
        let first = makeAuthorization(), second = makeAuthorization()
        XCTAssertNotEqual(first.state, second.state)
        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.verifier, second.verifier)
        let url = first.url.absoluteString
        XCTAssert(url.hasPrefix("https://iam.cyclocity.fr/realms/vls-default/protocol/openid-connect/auth?"))
        XCTAssertEqual(query(url, "client_id"), "vls-ios-lyon")
        XCTAssertEqual(query(url, "scope"), "openid email")
        XCTAssertEqual(query(url, "redirect_uri"), Cyclocity.callback)
        XCTAssertEqual(query(url, "code_challenge_method"), "S256")
        XCTAssertEqual(query(url, "code_challenge"), base64URL(Data(SHA256.hash(data: Data(first.verifier.utf8)))))
        XCTAssertEqual(query(url, "state"), first.state)
    }

    func testOnlyTheExpectedCallbackForThisLoginCanSupplyACode() throws {
        XCTAssertEqual(try readCallback("\(Cyclocity.callback)?state=expected&code=authorized", state: "expected"), "authorized")
        for url in [
            "\(Cyclocity.callback)?state=foreign&code=authorized", "\(Cyclocity.callback)?state=expected",
            "\(Cyclocity.callback)?state=expected&code=x&error=access_denied", "https://other.example/openid_connect_login?state=expected&code=x",
            "https://velov.grandlyon.com/other?state=expected&code=x"
        ] { XCTAssertThrowsError(try readCallback(url, state: "expected"), url) }
    }

    func testTheProvidersHiddenFormFieldsSurviveTheLoginStep() throws {
        let form = try readForm(loginPage, id: "kc-form-login")
        XCTAssertEqual(form.url.absoluteString, "https://iam.cyclocity.fr/realms/vls-default/login-actions/authenticate?session_code=abc&execution=e1&client_id=vls-ios-lyon")
        XCTAssertEqual(form.field("session"), "preserved")
        XCTAssertNil(form.field("username"))
        let device = try readForm(devicePage, id: "vls-form-device-id")
        XCTAssertEqual(device.fields.map(\.0), ["device_id", "tab_id"])
    }

    func testAnInvalidCredentialResponseAsksForANewLogin() {
        XCTAssertThrowsError(try readForm(#"<form id="kc-form-login" action="/realms/vls-default/login-actions/authenticate"></form>"#, id: "vls-form-device-id")) {
            XCTAssertEqual(($0 as? VelovError)?.code, .credentials)
        }
    }

    func testAnotherDeviceRefusalShowsTheOneDeviceMessage() {
        XCTAssertThrowsError(try readForm("<p>Ce compte est déjà en cours d&#39;utilisation sur un <b>autre appareil</b></p>", id: "vls-form-device-id")) {
            XCTAssertEqual(($0 as? VelovError)?.code, .device)
            XCTAssertEqual(($0 as? VelovError)?.message, "Votre compte est déjà connecté ailleurs (site ou autre appareil). Déconnectez-vous-y puis réessayez.")
        }
    }

    func testCredentialsAreNeverPostedToAFormOutsideTheIdentityProvider() async {
        let server = MockServer { _, _ in .status(200, body: #"<form id="kc-form-login" action="https://other.example/collect"><input name="username"/></form>"#) }
        do { _ = try await login(email: "person@example.com", code: "123456", deviceId: "test-device-0000", http: server.transport); XCTFail("no error") }
        catch { XCTAssertEqual((error as? VelovError)?.code, .protocol) }
        XCTAssertEqual(server.calls.count, 1)
    }

    /// The whole Keycloak dance, served by the mock realm.
    func realm(_ signer: TestSigner, deviceReply: Reply? = nil) -> MockServer {
        let state = Box<String>(), nonce = Box<String>()
        return MockServer { call, _ in
            let url = call.url
            if url.contains("/openid-connect/auth?") {
                state.value = query(url, "state"); nonce.value = query(url, "nonce")
                return .status(200, body: loginPage, headers: ["Set-Cookie": "AUTH_SESSION_ID=s1; Path=/realms/vls-default/; Secure; HttpOnly"])
            }
            if url.contains("/login-actions/authenticate") { return .status(200, body: devicePage, headers: ["Set-Cookie": "KC_RESTART=r2; Path=/realms/vls-default/"]) }
            if url.contains("/login-actions/required-action") {
                return deviceReply ?? .status(302, headers: ["Location": "\(Cyclocity.callback)?state=\(state.value!)&session_state=x&code=the-code"])
            }
            if url.hasSuffix("/openid-connect/token") {
                let now = Date().timeIntervalSince1970
                let id = signer.sign(["iss": Cyclocity.realm, "aud": "vls-ios-lyon", "nonce": nonce.value!, "exp": now + 300, "iat": now])
                return .json(["access_token": accessToken(expires: Date().addingTimeInterval(1800)), "refresh_token": "refresh-1", "id_token": id, "expires_in": 1800, "refresh_expires_in": 0])
            }
            if url.hasSuffix("/openid-connect/certs") { return .json(signer.jwks) }
            return .status(404)
        }
    }

    func testALoginPostsTheCredentialsThenTheStableDeviceIdThenExchangesTheCode() async throws {
        let server = realm(TestSigner())
        let tokens = try await login(email: "person@example.com", code: "123456", deviceId: "device-0123456789abcdef", http: server.transport)
        XCTAssertEqual(tokens.refreshToken, "refresh-1")
        let calls = server.calls
        XCTAssertEqual(calls.map(\.method), ["GET", "POST", "POST", "POST", "GET"])
        let credentials = parseForm(calls[1].body)
        XCTAssertEqual(credentials, ["session": "preserved", "username": "person@example.com", "password": "123456", "credentialId": ""])
        XCTAssertEqual(calls[1].header("Cookie"), "AUTH_SESSION_ID=s1")
        XCTAssertEqual(parseForm(calls[2].body), ["device_id": "device-0123456789abcdef", "tab_id": "t-1"])
        XCTAssertEqual(calls[2].header("Cookie"), "AUTH_SESSION_ID=s1; KC_RESTART=r2")
        let exchange = parseForm(calls[3].body)
        XCTAssertEqual(exchange["grant_type"], "authorization_code")
        XCTAssertEqual(exchange["client_id"], "vls-ios-lyon")
        XCTAssertEqual(exchange["code"], "the-code")
        XCTAssertEqual(codeChallenge(exchange["code_verifier"]!), query(calls[0].url, "code_challenge"))
        for call in calls { XCTAssert(call.url.hasPrefix("https://iam.cyclocity.fr/realms/vls-default/"), call.url) }
    }

    func testAnIdTokenFromAnotherKeyOrLoginIsRefused() async {
        let server = realm(TestSigner())
        let impostor = TestSigner()
        server.handler = { [handler = server.handler] call, index in
            call.url.hasSuffix("/certs") ? .json(impostor.jwks) : await handler(call, index)
        }
        do { _ = try await login(email: "person@example.com", code: "123456", deviceId: "device-0123456789abcdef", http: server.transport); XCTFail("no error") }
        catch { XCTAssertEqual((error as? VelovError)?.code, .protocol) }
    }

    func testTheOtherDeviceRefusalIsShownAndTheLoginIsNotRetried() async {
        let server = realm(TestSigner(), deviceReply: .status(400, body: "<p>Ce compte est déjà en cours d’utilisation sur un autre appareil</p>"))
        do { _ = try await login(email: "person@example.com", code: "123456", deviceId: "device-0123456789abcdef", http: server.transport); XCTFail("no error") }
        catch {
            XCTAssertEqual((error as? VelovError)?.code, .device)
            XCTAssertEqual((error as? VelovError)?.message, Messages.otherDevice)
        }
        XCTAssertEqual(server.calls.count, 3)
    }

    func testASessionRenewsWithItsRefreshTokenAndWithoutAPassword() async throws {
        let server = MockServer { _, _ in .json(["access_token": "new-access", "refresh_token": "new-refresh", "id_token": "new-identity", "expires_in": 1800, "refresh_expires_in": 2_500_000]) }
        let tokens = try await refreshTokens("existing-refresh", http: server.transport)
        XCTAssertEqual(tokens, Tokens(accessToken: "new-access", refreshToken: "new-refresh", idToken: "new-identity", expiresIn: 1800, refreshExpiresIn: 2_500_000))
        let call = server.calls[0]
        XCTAssertEqual(call.url, "\(Cyclocity.oidc)/token")
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(parseForm(call.body), ["grant_type": "refresh_token", "client_id": "vls-ios-lyon", "refresh_token": "existing-refresh"])
    }

    func testARejectedRefreshRevokesTheSessionAnOutageOrARedirectDoesNot() async {
        for (reply, revoked) in [(Reply.status(400), true), (.status(401), true), (.status(503), false), (.status(302, headers: ["Location": "https://elsewhere.example/"]), false)] {
            let server = MockServer { _, _ in reply }
            do { _ = try await refreshTokens("token", http: server.transport); XCTFail("no error") } catch {
                XCTAssertEqual((error as? VelovError)?.revoked, revoked, "\(reply)")
                XCTAssertEqual((error as? VelovError)?.code, revoked ? .expired : .unavailable)
            }
            XCTAssertEqual(server.calls.count, 1)
        }
    }

    func testALogoutPostsTheRefreshTokenAndReportsWhetherTheProviderConfirmed() async {
        let confirmed = MockServer { _, _ in .status(204) }
        let ended = await endSession(refreshToken: "rt", idToken: "it", http: confirmed.transport)
        XCTAssertTrue(ended)
        XCTAssertEqual(confirmed.calls.count, 1)
        XCTAssertEqual(confirmed.calls[0].url, "\(Cyclocity.oidc)/logout")
        XCTAssertEqual(confirmed.calls[0].method, "POST")
        XCTAssertEqual(parseForm(confirmed.calls[0].body), ["client_id": "vls-ios-lyon", "refresh_token": "rt"])
        let refused = await endSession(refreshToken: "rt", idToken: nil, http: MockServer { _, _ in .status(400) }.transport)
        XCTAssertFalse(refused)
        let offline = await endSession(refreshToken: "rt", idToken: nil, http: MockServer { _, _ in .failure(.notConnectedToInternet) }.transport)
        XCTAssertFalse(offline)
        let hint = MockServer { _, _ in .status(302) }
        let byHint = await endSession(refreshToken: nil, idToken: "it", http: hint.transport)
        XCTAssertTrue(byHint)
        XCTAssertEqual(query(hint.calls[0].url, "id_token_hint"), "it")
        XCTAssertEqual(hint.calls[0].method, "GET")
    }

    func testTheAccountEmailIsReadFromAnAccessTokenOfThisClient() throws {
        XCTAssertEqual(try accountEmail(accessToken: accessToken(expires: Date())), "person@example.com")
        let foreign = base64URL(Data(#"{"alg":"none"}"#.utf8)) + "." + base64URL(Data(#"{"azp":"vls-web-lyon","preferred_username":"person@example.com"}"#.utf8)) + ".x"
        XCTAssertThrowsError(try accountEmail(accessToken: foreign))
        XCTAssertThrowsError(try accountEmail(accessToken: "garbage"))
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T?
}
