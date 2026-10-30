import Foundation

enum HTML {
    static func attributes(_ tag: Substring) -> [String: String] {
        var result: [String: String] = [:]
        let body = tag.drop { $0 != " " && $0 != "\t" && $0 != "\n" && $0 != "\r" && $0 != ">" }
        for match in body.matches(of: /([^\s=\/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/) {
            let name = String(match.output.1).lowercased()
            let value = match.output.2 ?? match.output.3 ?? match.output.4 ?? ""
            if result[name] == nil { result[name] = decodeEntities(String(value)) }
        }
        return result
    }

    static func tags(_ name: String, in html: Substring) -> [(range: Range<String.Index>, attributes: [String: String])] {
        let pattern = try! Regex("<\(name)\\b[^>]*>").ignoresCase()
        return html.matches(of: pattern).map { ($0.range, attributes(html[$0.range].dropFirst().dropLast())) }
    }

    static func text(_ html: String) -> String {
        let withoutCode = html.replacing(try! Regex("<(script|style)\\b[^>]*>.*?</\\1\\s*>").ignoresCase().dotMatchesNewlines(), with: " ")
        return decodeEntities(withoutCode.replacing(/<[^>]*>/, with: " "))
    }

    static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "rsquo": "’", "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç"]
        return value.replacing(/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);/) { match -> String in
            let entity = String(match.output.1)
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                return UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            if entity.hasPrefix("#") {
                return UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            return named[entity] ?? String(match.output.0)
        }
    }
}

public struct LoginForm: Equatable, Sendable {
    public let url: URL
    public private(set) var fields: [(String, String)]

    public static func == (left: LoginForm, right: LoginForm) -> Bool {
        left.url == right.url && left.fields.map(\.0) == right.fields.map(\.0) && left.fields.map(\.1) == right.fields.map(\.1)
    }

    public func field(_ name: String) -> String? { fields.first { $0.0 == name }?.1 }

    public mutating func set(_ name: String, _ value: String) {
        if let index = fields.firstIndex(where: { $0.0 == name }) {
            fields[index].1 = value
            fields = fields.enumerated().filter { $0.offset == index || $0.element.0 != name }.map(\.element)
        } else {
            fields.append((name, value))
        }
    }
}

func serverRefusal(_ html: String) -> String? {
    let collapse = { (text: String) in text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    let page = Substring(html)
    let all = HTML.text(html)
    if ["autre appareil", "another device"].contains(where: { all.range(of: $0, options: .caseInsensitive) != nil }) { return Messages.otherDevice }
    for tag in HTML.tags("[a-z]+[0-9]?", in: page) {
        let classes = (tag.attributes["class"] ?? "").split(separator: " ")
        guard classes.contains(where: { $0 == "kc-feedback-text" || $0 == "alert-error" }) || tag.attributes["id"] == "input-error" else { continue }
        let name = page[tag.range].dropFirst().prefix { $0.isLetter || $0.isNumber }
        let rest = page[tag.range.upperBound...]
        let end = rest.range(of: "</\(name)", options: .caseInsensitive)?.lowerBound ?? rest.endIndex
        let text = collapse(HTML.text(String(rest[..<end])))
        if !text.isEmpty { return text }
    }
    return nil
}

public func safeIAMURL(_ value: String, relativeTo base: URL? = nil) throws -> URL {
    guard let url = URL(string: value, relativeTo: base ?? URL(string: Cyclocity.iam))?.absoluteURL,
          url.scheme == "https", url.host == "iam.cyclocity.fr", url.port == nil, url.path.hasPrefix("/realms/vls-default/") else {
        throw VelovError(.protocol, "Connexion impossible. Réessayez dans un instant.")
    }
    return url
}

public func readForm(_ html: String, id: String) throws -> LoginForm {
    let page = Substring(html)
    let forms = HTML.tags("form", in: page).filter { $0.attributes["id"] == id }
    guard forms.count == 1, let action = forms[0].attributes["action"], !action.isEmpty else {
        if id == "vls-form-device-id", HTML.tags("[a-z]+", in: page).contains(where: { $0.attributes["id"] == "kc-form-login" }) {
            throw VelovError(.credentials, Messages.credentials)
        }
        if let message = serverRefusal(html) { throw VelovError(.refused, message) }
        throw VelovError(.protocol, "Une étape supplémentaire est demandée. Connectez-vous d’abord sur l’app ou le site Vélo’v.")
    }
    let start = forms[0].range.upperBound
    let end = page[start...].range(of: "</form", options: .caseInsensitive)?.lowerBound ?? page.endIndex
    var form = LoginForm(url: try safeIAMURL(action), fields: [])
    for input in HTML.tags("input", in: page[start..<end]) where input.attributes["type"]?.lowercased() == "hidden" {
        if let name = input.attributes["name"], !name.isEmpty { form.set(name, input.attributes["value"] ?? "") }
    }
    return form
}
