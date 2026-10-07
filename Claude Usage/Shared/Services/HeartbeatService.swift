import Foundation

/// Keeps the latest daily activity record on this Mac. No network request is made.
final class HeartbeatService {
    static let shared = HeartbeatService()

    private let defaults: UserDefaults
    private let lastRecordKey = "heartbeat.localRecordedAt"
    private let versionKey = "heartbeat.localVersion"
    private let interval: TimeInterval = 86_400 // 24 hours
    private var timer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records immediately if due, then keeps the existing daily cadence.
    func start() {
        recordIfNeeded()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.recordIfNeeded()
        }
        timer?.tolerance = 3600 // 1hr tolerance for energy efficiency
    }

    func recordIfNeeded(now: Date = Date(), version: String? = nil) {
        let lastRecord = defaults.object(forKey: lastRecordKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(lastRecord) >= interval else { return }
        let appVersion = version
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown"
        defaults.set(appVersion, forKey: versionKey)
        defaults.set(now, forKey: lastRecordKey)
    }
}
