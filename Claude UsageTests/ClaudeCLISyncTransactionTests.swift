import XCTest
@testable import Claude_Usage

@MainActor
final class ClaudeCLISyncTransactionTests: XCTestCase {
    private func credentials(token: String = "synthetic-access", expiry: TimeInterval? = nil) -> String {
        var oauth: [String: Any] = ["accessToken": token]
        if let expiry { oauth["expiresAt"] = expiry }
        return String(data: try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth]), encoding: .utf8)!
    }

    func testIncompleteAndBlankTokensCannotReportSuccessfulSync() {
        let profile = Profile(name: "Synthetic")
        for json in ["{}", credentials(token: ""), credentials(token: "  ")] {
            var saved = false
            XCTAssertThrowsError(try ClaudeCodeSyncService.shared.syncToProfile(profile.id,
                readCredentials: { json }, readAccount: { nil }, loadProfiles: { [profile] },
                saveProfiles: { _ in saved = true; return true }))
            XCTAssertFalse(saved)
        }
    }

    func testExpiredTokenCannotBeSyncedAsReady() {
        let profile = Profile(name: "Synthetic")
        for multiplier in [1.0, 1000.0] {
            var saved = false
            let json = credentials(expiry: Date().addingTimeInterval(-120).timeIntervalSince1970 * multiplier)
            XCTAssertThrowsError(try ClaudeCodeSyncService.shared.syncToProfile(profile.id,
                readCredentials: { json }, readAccount: { nil }, loadProfiles: { [profile] },
                saveProfiles: { _ in saved = true; return true }))
            XCTAssertFalse(saved)
        }
    }

    func testSecureSaveFailureIsReported() {
        let profile = Profile(name: "Synthetic")
        let json = credentials(expiry: Date().addingTimeInterval(3600).timeIntervalSince1970)
        XCTAssertThrowsError(try ClaudeCodeSyncService.shared.syncToProfile(profile.id,
            readCredentials: { json }, readAccount: { nil }, loadProfiles: { [profile] }, saveProfiles: { _ in false }))
    }

    func testMalformedExpiryCannotBeCommittedAsSuccessfulSync() throws {
        let profile = Profile(name: "Synthetic")
        for expiry in [true, -1, "not a timestamp"] as [Any] {
            let json = String(decoding: try JSONSerialization.data(withJSONObject:
                ["claudeAiOauth": ["accessToken": "synthetic-access", "expiresAt": expiry]]), as: UTF8.self)
            var saved = false
            XCTAssertThrowsError(try ClaudeCodeSyncService.shared.syncToProfile(profile.id,
                readCredentials: { json }, readAccount: { nil }, loadProfiles: { [profile] },
                saveProfiles: { _ in saved = true; return true }))
            XCTAssertFalse(saved)
        }
    }

    func testLegacySnapshotWithoutExpiryCanBeSavedButRemainsUnverified() throws {
        let profile = Profile(name: "Synthetic")
        let json = credentials()
        var saved = false
        try ClaudeCodeSyncService.shared.syncToProfile(profile.id,
            readCredentials: { json }, readAccount: { nil }, loadProfiles: { [profile] },
            saveProfiles: { _ in saved = true; return true })
        XCTAssertTrue(saved)
        XCTAssertEqual(ClaudeCLIStatus.resolve(credentialsJSON: json), .expiryUnknown)
    }

    func testMetadataAndCredentialsAreCommittedTogetherOnlyForTarget() throws {
        let original = Profile(name: "Target")
        let other = Profile(name: "Other", cliCredentialsJSON: "preserved-other")
        let json = credentials(expiry: Date().addingTimeInterval(3600).timeIntervalSince1970)
        var writes: [[Profile]] = []
        try ClaudeCodeSyncService.shared.syncToProfile(original.id,
            readCredentials: { json }, readAccount: { "{\"accountUuid\":\"synthetic-personal\"}" },
            loadProfiles: { [original, other] }, saveProfiles: { writes.append($0); return true })
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes[0][0].cliCredentialsJSON, json)
        XCTAssertTrue(writes[0][0].hasCliAccount)
        XCTAssertNotNil(writes[0][0].cliAccountSyncedAt)
        XCTAssertEqual(writes[0][0].oauthAccountJSON, "{\"accountUuid\":\"synthetic-personal\"}")
        XCTAssertEqual(writes[0][1], other)
    }

    func testMissingTargetDoesNotCommit() {
        var saved = false
        XCTAssertThrowsError(try ClaudeCodeSyncService.shared.syncToProfile(UUID(),
            readCredentials: { self.credentials() }, readAccount: { nil }, loadProfiles: { [] },
            saveProfiles: { _ in saved = true; return true }))
        XCTAssertFalse(saved)
    }
}
