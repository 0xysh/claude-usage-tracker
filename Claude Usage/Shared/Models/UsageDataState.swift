import Foundation

/// Whether a displayed reading is current, cached, or has never been received.
enum UsageDataState: Equatable {
    case unavailable
    case fresh
    case lastKnown

    static func resolve(lastUpdated: Date?, refreshFailed: Bool, now: Date = Date()) -> Self {
        guard let lastUpdated else { return .unavailable }
        return refreshFailed || now.timeIntervalSince(lastUpdated) > 300 ? .lastKnown : .fresh
    }
}
