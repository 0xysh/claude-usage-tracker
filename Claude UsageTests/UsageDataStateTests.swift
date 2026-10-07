import XCTest
@testable import Claude_Usage

@MainActor
final class UsageDataStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMissingReadingNeverAppearsAsFreshEvenWithoutAnError() async {
        XCTAssertEqual(UsageDataState.resolve(lastUpdated: nil, refreshFailed: false, now: now), .unavailable)
        XCTAssertEqual(UsageDataState.resolve(lastUpdated: nil, refreshFailed: true, now: now), .unavailable)
    }

    func testSuccessfulRecentReadingIsFresh() async {
        XCTAssertEqual(UsageDataState.resolve(lastUpdated: now.addingTimeInterval(-30), refreshFailed: false, now: now), .fresh)
    }

    func testFiveMinuteBoundaryAndOlderReading() async {
        XCTAssertEqual(UsageDataState.resolve(lastUpdated: now.addingTimeInterval(-300), refreshFailed: false, now: now), .fresh)
        XCTAssertEqual(UsageDataState.resolve(lastUpdated: now.addingTimeInterval(-301), refreshFailed: false, now: now), .lastKnown)
    }

    func testFailedRefreshLabelsEvenRecentCachedDataAsLastKnown() async {
        XCTAssertEqual(UsageDataState.resolve(lastUpdated: now, refreshFailed: true, now: now), .lastKnown)
    }

    func testFutureDatedCacheCannotAppearFresh() async {
        XCTAssertEqual(UsageDataState.resolve(lastUpdated: now.addingTimeInterval(600), refreshFailed: false, now: now), .lastKnown)
        XCTAssertEqual(UsageDataState.resolve(lastUpdated: now.addingTimeInterval(30), refreshFailed: false, now: now), .fresh)
    }
}
