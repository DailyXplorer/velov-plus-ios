import Foundation
import Security

public func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

public func base64URLDecode(_ value: some StringProtocol) -> Data? {
    var text = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    text += String(repeating: "=", count: (4 - text.count % 4) % 4)
    return Data(base64Encoded: text)
}

public struct JWT: Sendable {
    public let header: JSON
    public let payload: JSON
    let signingInput: Data
    let signature: Data

    public init?(_ token: String) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let header = base64URLDecode(parts[0]).flatMap(JSON.parse), let payload = base64URLDecode(parts[1]).flatMap(JSON.parse),
              let signature = base64URLDecode(parts[2]) else { return nil }
        self.header = header
        self.payload = payload
        self.signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        self.signature = signature
    }

    public func verifiesRS256(jwks: JSON) -> Bool {
        guard header["alg"]?.string == "RS256", let keys = jwks["keys"]?.array else { return false }
        let kid = header["kid"]?.string
        return keys.contains { key in
            guard key["kty"]?.string == "RSA", kid == nil || key["kid"]?.string == kid,
                  let modulus = key["n"]?.string.flatMap(base64URLDecode), let exponent = key["e"]?.string.flatMap(base64URLDecode),
                  let publicKey = rsaPublicKey(modulus: modulus, exponent: exponent) else { return false }
            return SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, signingInput as CFData, signature as CFData, nil)
        }
    }
}

func rsaPublicKey(modulus: Data, exponent: Data) -> SecKey? {
    func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 { bytes.insert(UInt8(value & 0xff), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    func integer(_ bytes: Data) -> Data {
        var value = Data(bytes.drop { $0 == 0 })
        if value.isEmpty || value.first! & 0x80 != 0 { value.insert(0, at: 0) }
        return Data([0x02]) + length(value.count) + value
    }
    let body = integer(modulus) + integer(exponent)
    let der = Data([0x30]) + length(body.count) + body
    let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
    return SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil)
}
