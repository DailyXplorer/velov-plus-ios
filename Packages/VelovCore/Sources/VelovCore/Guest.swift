import Foundation

public enum StartMode: Equatable, Sendable {
    case session, guest, signedOut

    public init(hasSession: Bool, guest: Bool) {
        self = hasSession ? .session : guest ? .guest : .signedOut
    }
}

public struct GuestStore {
    static let modeKey = "guest.mode"
    static let favoritesKey = "guest.favorites"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var isOn: Bool { defaults.bool(forKey: Self.modeKey) }

    public func remember(_ on: Bool) {
        if on { defaults.set(true, forKey: Self.modeKey) } else { defaults.removeObject(forKey: Self.modeKey) }
    }

    public var favorites: [Int] {
        var list: [Int] = []
        for case let number as Int in defaults.array(forKey: Self.favoritesKey) ?? [] where number > 0 && !list.contains(number) { list.append(number) }
        return list
    }

    @discardableResult
    public func setFavorite(_ number: Int, _ on: Bool) -> [Int] {
        let list = favorites.filter { $0 != number } + (on ? [number] : [])
        defaults.set(list, forKey: Self.favoritesKey)
        return list
    }
}
