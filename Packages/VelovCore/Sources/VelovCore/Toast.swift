import Foundation

public enum ToastAction: Equatable, Sendable {
    case openSettings
}

public struct Toast: Equatable, Sendable, Identifiable {
    public let id: Int
    public let message: String
    public let action: ToastAction?
}

public struct ToastSlot: Equatable, Sendable {
    public private(set) var current: Toast?
    private var issued = 0

    public init() {}

    @discardableResult
    public mutating func show(_ message: String, action: ToastAction? = nil) -> Toast {
        issued += 1
        let toast = Toast(id: issued, message: message, action: action)
        current = toast
        return toast
    }

    public mutating func dismiss(_ id: Int) {
        if current?.id == id { current = nil }
    }
}
