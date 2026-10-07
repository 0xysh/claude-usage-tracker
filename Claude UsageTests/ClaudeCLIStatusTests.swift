import XCTest
@testable import Claude_Usage

@MainActor
final class ClaudeCLIStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func savedCredentials(token: Any = "synthetic-access", expiry: Any? = nil) throws -> String {
        var oauth: [String: Any] = ["accessToken": token]
        oauth["expiresAt"] = expiry
        return String(decoding: try JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth]), as: UTF8.self)
    }

    func testAbsentSavedCredentialsAreNotReady() {
        let status = ClaudeCLIStatus.resolve(credentialsJSON: nil, now: now)
        XCTAssertEqual(status, .notSaved)
        XCTAssertFalse(status.isReadyLocally)
    }

    func testMalformedOrIncompleteJSONIsNotReady() {
        for json in ["", "not json", "[]", "{}", "{\"claudeAiOauth\":{}}"] {
            let status = ClaudeCLIStatus.resolve(credentialsJSON: json, now: now)
            XCTAssertEqual(status, .incomplete)
            XCTAssertFalse(status.isReadyLocally)
        }
    }

    func testBlankAndInvalidTokenValuesAreNotReady() throws {
        for token in ["", " \n\t ", 123, false, NSNull()] as [Any] {
            let status = ClaudeCLIStatus.resolve(credentialsJSON: try savedCredentials(token: token), now: now)
            XCTAssertEqual(status, .incomplete)
            XCTAssertFalse(status.isReadyLocally)
        }
    }

    func testFutureSecondsExpiryIsReadyLocally() throws {
        let json = try savedCredentials(expiry: now.timeIntervalSince1970 + 3600)
        XCTAssertEqual(ClaudeCLIStatus.resolve(credentialsJSON: json, now: now), .ready)
        XCTAssertTrue(ClaudeCLIStatus.resolve(credentialsJSON: json, now: now).isReadyLocally)
    }

    func testFutureMillisecondsExpiryIsReadyLocally() throws {
        let json = try savedCredentials(expiry: (now.timeIntervalSince1970 + 3600) * 1000)
        XCTAssertEqual(ClaudeCLIStatus.resolve(credentialsJSON: json, now: now), .ready)
    }

    func testExpiredSecondsSnapshotNeedsLogin() throws {
        let json = try savedCredentials(expiry: now.timeIntervalSince1970 - 1)
        let status = ClaudeCLIStatus.resolve(credentialsJSON: json, now: now)
        XCTAssertEqual(status, .expired)
        XCTAssertFalse(status.isReadyLocally)
    }

    func testExpiredMillisecondsSnapshotNeedsLogin() throws {
        let json = try savedCredentials(expiry: (now.timeIntervalSince1970 - 1) * 1000)
        XCTAssertEqual(ClaudeCLIStatus.resolve(credentialsJSON: json, now: now), .expired)
    }

    func testSnapshotAtExpiryIsExpired() throws {
        let json = try savedCredentials(expiry: now.timeIntervalSince1970)
        XCTAssertEqual(ClaudeCLIStatus.resolve(credentialsJSON: json, now: now), .expired)
    }

    func testMissingExpiryIsNeutralRatherThanGreen() throws {
        let status = ClaudeCLIStatus.resolve(credentialsJSON: try savedCredentials(), now: now)
        XCTAssertEqual(status, .expiryUnknown)
        XCTAssertFalse(status.isReadyLocally)
    }

    func testNullExpiryIsNeutralRatherThanGreen() throws {
        let json = try savedCredentials(expiry: NSNull())
        XCTAssertEqual(ClaudeCLIStatus.resolve(credentialsJSON: json, now: now), .expiryUnknown)
    }

    func testInvalidExpiryDoesNotMakeCredentialsReady() throws {
        for expiry in [true, -1, "NaN", "not a timestamp"] as [Any] {
            let status = ClaudeCLIStatus.resolve(credentialsJSON: try savedCredentials(expiry: expiry), now: now)
            XCTAssertEqual(status, .incomplete)
            XCTAssertFalse(status.isReadyLocally)
        }
    }

    func testSnapshotBecomesExpiredWithoutCredentialMutation() throws {
        let expiry = now.timeIntervalSince1970 + 10
        let json = try savedCredentials(expiry: expiry)
        XCTAssertEqual(ClaudeCLIStatus.resolve(credentialsJSON: json, now: now), .ready)
        XCTAssertEqual(ClaudeCLIStatus.resolve(credentialsJSON: json, now: now.addingTimeInterval(11)), .expired)
    }
}
