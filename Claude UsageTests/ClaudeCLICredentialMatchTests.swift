import XCTest
@testable import Claude_Usage

/// Pure synthetic fixtures exercise the real selector's identity check without
/// accessing a login store, Keychain item, credential file or provider endpoint.
final class ClaudeCLICredentialMatchTests: XCTestCase {
    private var service: ClaudeCodeSyncService { .shared }

    private func credentials(refreshToken: String? = nil) -> String {
        var oauth = ["accessToken": "synthetic-access"]
        oauth["refreshToken"] = refreshToken
        return String(data: try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth]), encoding: .utf8)!
    }

    private func account(_ id: String) -> String { "{\"accountUuid\":\"\(id)\"}" }

    func testMissingIdentitiesAndRefreshTokensDoNotEstablishAMatch() {
        let profile = Profile(name: "Synthetic A", cliCredentialsJSON: credentials())
        XCTAssertFalse(service.systemCredentialsMatchProfile(credentials(), profile: profile, systemAccountJSON: nil))
    }

    func testMissingSavedCredentialsDoNotEstablishAMatch() {
        let profile = Profile(name: "Synthetic A")
        XCTAssertFalse(service.systemCredentialsMatchProfile(credentials(), profile: profile, systemAccountJSON: nil))
    }

    func testEmptyRefreshTokensDoNotEstablishAMatch() {
        let profile = Profile(name: "Synthetic A", cliCredentialsJSON: credentials(refreshToken: ""))
        XCTAssertFalse(service.systemCredentialsMatchProfile(credentials(refreshToken: ""), profile: profile, systemAccountJSON: nil))
    }

    func testWhitespaceOnlyRefreshTokensDoNotEstablishAMatch() {
        let profile = Profile(name: "Synthetic A", cliCredentialsJSON: credentials(refreshToken: "  "))
        XCTAssertFalse(service.systemCredentialsMatchProfile(credentials(refreshToken: "  "), profile: profile, systemAccountJSON: nil))
    }

    func testDifferentKnownAccountsOverrideAnApparentlyMatchingLineage() {
        let profile = Profile(name: "Synthetic A", cliCredentialsJSON: credentials(refreshToken: "synthetic-lineage"),
                              oauthAccountJSON: account("account-a"))
        XCTAssertFalse(service.systemCredentialsMatchProfile(credentials(refreshToken: "synthetic-lineage"),
                                                            profile: profile, systemAccountJSON: account("account-b")))
    }

    func testMatchingKnownAccountsDoNotRequireRefreshTokens() {
        let profile = Profile(name: "Synthetic A", cliCredentialsJSON: credentials(), oauthAccountJSON: account("account-a"))
        XCTAssertTrue(service.systemCredentialsMatchProfile(credentials(), profile: profile, systemAccountJSON: account("account-a")))
    }

    func testMatchingNonemptyLineageWorksWhenMetadataIsUnavailable() {
        let profile = Profile(name: "Synthetic A", cliCredentialsJSON: credentials(refreshToken: "synthetic-lineage"))
        XCTAssertTrue(service.systemCredentialsMatchProfile(credentials(refreshToken: "synthetic-lineage"), profile: profile,
                                                           systemAccountJSON: nil))
    }

    func testDifferentLineagesDoNotEstablishAMatch() {
        let profile = Profile(name: "Synthetic A", cliCredentialsJSON: credentials(refreshToken: "synthetic-a"))
        XCTAssertFalse(service.systemCredentialsMatchProfile(credentials(refreshToken: "synthetic-b"), profile: profile,
                                                            systemAccountJSON: nil))
    }
}
