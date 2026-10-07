import Foundation

/// Whether a displayed reading is current, cached, or has never been received.
enum UsageDataState: Equatable {
    case unavailable
    case fresh
    case lastKnown

    static func resolve(lastUpdated: Date?, refreshFailed: Bool, now: Date = Date()) -> Self {
        guard let lastUpdated else { return .unavailable }
        let age = now.timeIntervalSince(lastUpdated)
        // A substantially future-dated cache is not evidence of a recent fetch.
        return refreshFailed || age > 300 || age < -60 ? .lastKnown : .fresh
    }
}
