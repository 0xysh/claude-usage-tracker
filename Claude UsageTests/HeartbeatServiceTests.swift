import XCTest
@testable import Claude_Usage

final class HeartbeatServiceTests: XCTestCase {
    func testRecordsVersionAndDateLocally() throws {
        let suite = "HeartbeatServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = HeartbeatService(defaults: defaults)
        let now = Date(timeIntervalSince1970: 100_000)

        service.recordIfNeeded(now: now, version: "personal-1")

        XCTAssertEqual(defaults.string(forKey: "heartbeat.localVersion"), "personal-1")
        XCTAssertEqual(defaults.object(forKey: "heartbeat.localRecordedAt") as? Date, now)
    }

    func testDoesNotRecordAgainBeforeTwentyFourHours() throws {
        let suite = "HeartbeatServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = HeartbeatService(defaults: defaults)
        let first = Date(timeIntervalSince1970: 100_000)
        service.recordIfNeeded(now: first, version: "personal-1")

        service.recordIfNeeded(now: first.addingTimeInterval(86_399), version: "personal-2")
        XCTAssertEqual(defaults.string(forKey: "heartbeat.localVersion"), "personal-1")

        service.recordIfNeeded(now: first.addingTimeInterval(86_400), version: "personal-2")
        XCTAssertEqual(defaults.string(forKey: "heartbeat.localVersion"), "personal-2")
    }

    func testOldRemotePingDoesNotSuppressFirstLocalRecord() throws {
        let suite = "HeartbeatServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 100_000)
        defaults.set(now, forKey: "heartbeat.lastPingDate")

        HeartbeatService(defaults: defaults).recordIfNeeded(now: now, version: "personal-1")

        XCTAssertEqual(defaults.string(forKey: "heartbeat.localVersion"), "personal-1")
    }
}
