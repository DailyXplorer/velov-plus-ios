import Foundation

public enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public static func parse(_ data: Data) -> JSON? {
        try? JSONDecoder().decode(JSON.self, from: data)
    }

    public subscript(key: String) -> JSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var int: Int? {
        guard let value = number, value.rounded() == value, abs(value) <= 9_007_199_254_740_991 else { return nil }
        return Int(value)
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var array: [JSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var object: [String: JSON]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool { self == .null }
}

extension JSON: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

struct ShapeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

extension Optional where Wrapped == JSON {
    var isMissing: Bool { self == nil || self == .null }

    func nullishString(_ field: String) throws -> String? {
        guard let value = self, value != .null else { return nil }
        guard let string = value.string else { throw ShapeError("\(field) is not a string") }
        return string
    }

    func nullishNumber(_ field: String) throws -> Double? {
        guard let value = self, value != .null else { return nil }
        guard let number = value.number else { throw ShapeError("\(field) is not a number") }
        return number
    }

    func nullishBool(_ field: String) throws -> Bool? {
        guard let value = self, value != .null else { return nil }
        guard let bool = value.bool else { throw ShapeError("\(field) is not a boolean") }
        return bool
    }
}
