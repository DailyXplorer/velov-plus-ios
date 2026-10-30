import Foundation
import Observation

@MainActor
@Observable
public final class LatestLoad {
    private var flight: Task<Void, Never>?
    @ObservationIgnored private var stale = false

    public init() {}

    public var running: Bool { flight != nil }

    public func run<T>(_ fetch: @escaping @MainActor () async -> T?, apply: @escaping @MainActor (T) -> Void) async {
        if let flight {
            stale = true
            return await flight.value
        }
        let task = Task {
            repeat {
                stale = false
                guard let value = await fetch() else { return }
                if !stale { apply(value) }
            } while stale
        }
        flight = task
        await task.value
        if flight == task { flight = nil }
    }

    public func changed() {
        if flight != nil { stale = true }
    }

    public func reset() {
        flight = nil
        stale = false
    }
}
