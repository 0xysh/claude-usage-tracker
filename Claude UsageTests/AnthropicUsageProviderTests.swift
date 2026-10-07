import XCTest
@testable import Claude_Usage

@MainActor
final class AnthropicUsageProviderTests: XCTestCase {
    func testActiveRefreshUsesProfileAwareCLISelector() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic", cliCredentialsJSON: "saved", customKeychainServiceName: "synthetic-pin")
        source.selectedJSON = "fresh"
        source.tokens["fresh"] = "synthetic-fresh-token"
        let provider = makeProvider(api, source, activeID: profile.id)

        _ = try await provider.fetchUsageForActiveProfile(profile)
        XCTAssertEqual(source.selectedIDs, [profile.id])
        XCTAssertEqual(source.allowRotationValues, [false])
        XCTAssertEqual(api.oauthTokens, ["synthetic-fresh-token"])
        XCTAssertEqual(api.genericFetchCount, 0)
    }

    func testBrowserOrganizationLookupUsesRequestedProfileWhileDifferentProfileIsActive() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic A", claudeSessionKey: "synthetic-browser-session-A")
        let activeProfile = Profile(name: "Synthetic B", claudeSessionKey: "synthetic-browser-session-B", organizationId: "synthetic-org-B")
        api.syntheticActiveProfile = activeProfile
        let provider = makeProvider(api, source, activeID: activeProfile.id)

        _ = try await provider.fetchUsage(for: profile)
        XCTAssertEqual(api.events, ["all-organizations", "browser-usage"])
        XCTAssertEqual(api.organizationSessionKeys, ["synthetic-browser-session-A"])
        XCTAssertEqual(api.browserSessionKeys, ["synthetic-browser-session-A"])
        XCTAssertEqual(api.sessionOrganizations, ["synthetic-org-A"])
        XCTAssertEqual(api.activeOrganizationHelperCount, 0)
        XCTAssertEqual(api.syntheticActiveProfile, activeProfile)
        XCTAssertTrue(source.selectedIDs.isEmpty)
        XCTAssertEqual(source.systemReadCount, 0)
    }

    func testEmptyBrowserOrganizationsFailsWithoutUsageRequestOrActiveProfileMutation() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic A", claudeSessionKey: "synthetic-browser-session-A")
        let activeProfile = Profile(name: "Synthetic B", organizationId: "synthetic-org-B")
        api.syntheticActiveProfile = activeProfile
        api.organizations = []
        let provider = makeProvider(api, source, activeID: activeProfile.id)

        await assertFailure(.apiParsingFailed) { try await provider.fetchUsage(for: profile) }
        XCTAssertEqual(api.organizationSessionKeys, ["synthetic-browser-session-A"])
        XCTAssertTrue(api.sessionOrganizations.isEmpty)
        XCTAssertEqual(api.activeOrganizationHelperCount, 0)
        XCTAssertEqual(api.syntheticActiveProfile, activeProfile)
    }

    func testExpiredCLIThrowsWhileRetainingLastKnownUsage() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        var cached = ClaudeUsage.empty
        cached.sessionPercentage = 37
        let profile = Profile(name: "Synthetic", cliCredentialsJSON: "expired", claudeUsage: cached)
        source.selectedJSON = "expired"
        source.tokens["expired"] = "synthetic-expired-token"
        source.expired.insert("expired")
        let provider = makeProvider(api, source, activeID: profile.id)

        await assertFailure(.sessionKeyExpired) { try await provider.fetchUsage(for: profile) }
        XCTAssertEqual(profile.claudeUsage, cached)
        XCTAssertTrue(api.oauthTokens.isEmpty)
        XCTAssertTrue(provider.hasCredentials(for: profile), "Allow refresh to explain expired credentials instead of skipping it")
    }

    func testMissingOrEmptyTokenThrowsInvalidWithoutReturningCacheAsFresh() async throws {
        for token in [nil, "", "   "] as [String?] {
            let api = SyntheticAnthropicAPI()
            let source = SyntheticAnthropicCLI()
            let profile = Profile(name: "Synthetic", cliCredentialsJSON: "malformed", claudeUsage: .empty)
            source.selectedJSON = "malformed"
            source.tokens["malformed"] = token
            let provider = makeProvider(api, source, activeID: profile.id)
            await assertFailure(.sessionKeyInvalid) { try await provider.fetchUsage(for: profile) }
            XCTAssertTrue(api.oauthTokens.isEmpty)
        }
    }

    func testDifferentSystemAccountCannotReplaceBoundProfile() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic", cliCredentialsJSON: "malformed", oauthAccountJSON: "profile-account")
        source.selectedJSON = "malformed"
        source.systemJSON = "system-valid"
        source.systemAccount = "other-account"
        source.tokens["system-valid"] = "synthetic-other-token"
        let provider = makeProvider(api, source, activeID: profile.id)

        await assertFailure(.sessionKeyInvalid) { try await provider.fetchUsage(for: profile) }
        XCTAssertTrue(api.oauthTokens.isEmpty)
    }

    func testAccountMatchedSystemFallbackRemainsAvailable() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic", cliCredentialsJSON: "malformed", oauthAccountJSON: "same-account")
        source.selectedJSON = "malformed"
        source.systemJSON = "system-valid"
        source.systemAccount = "same-account"
        source.tokens["system-valid"] = "synthetic-system-token"
        let provider = makeProvider(api, source, activeID: profile.id)

        _ = try await provider.fetchUsage(for: profile)
        XCTAssertEqual(api.oauthTokens, ["synthetic-system-token"])
    }

    func testMatchingRefreshLineageAllowsFallbackWhenAccountMetadataIsAbsent() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic", cliCredentialsJSON: "saved")
        source.selectedJSON = "saved"
        source.systemJSON = "system-valid"
        source.tokens["system-valid"] = "synthetic-system-token"
        source.refreshTokens["saved"] = "synthetic-lineage"
        source.refreshTokens["system-valid"] = "synthetic-lineage"
        let provider = makeProvider(api, source, activeID: profile.id)

        _ = try await provider.fetchUsage(for: profile)
        XCTAssertEqual(api.oauthTokens, ["synthetic-system-token"])
    }

    func testUnknownAccountAndMissingLineageCannotCountAsAccountMatch() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic", cliCredentialsJSON: "malformed")
        source.selectedJSON = "malformed"
        source.systemJSON = "system-valid"
        source.tokens["system-valid"] = "synthetic-other-token"
        let provider = makeProvider(api, source, activeID: profile.id)

        await assertFailure(.sessionKeyInvalid) { try await provider.fetchUsage(for: profile) }
        XCTAssertTrue(api.oauthTokens.isEmpty)
    }

    func testNonactiveProfileNeverReadsGenericSystemCredentials() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic", cliCredentialsJSON: "malformed")
        source.systemJSON = "system-valid"
        source.tokens["system-valid"] = "synthetic-system-token"
        let provider = makeProvider(api, source, activeID: UUID())

        await assertFailure(.sessionKeyInvalid) { try await provider.fetchUsage(for: profile) }
        XCTAssertEqual(source.systemReadCount, 0)
        XCTAssertTrue(api.oauthTokens.isEmpty)
    }

    func testUnboundActiveProfilePreservesInitialSystemCLIFallback() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "Synthetic")
        source.systemJSON = "system-valid"
        source.tokens["system-valid"] = "synthetic-system-token"
        let provider = makeProvider(api, source, activeID: profile.id)

        _ = try await provider.fetchUsage(for: profile)
        XCTAssertEqual(api.oauthTokens, ["synthetic-system-token"])
    }

    func testFailureDiagnosticsContainOnlySelectionBooleans() async throws {
        let api = SyntheticAnthropicAPI()
        let source = SyntheticAnthropicCLI()
        let profile = Profile(name: "synthetic-private-name", cliCredentialsJSON: "expired", customKeychainServiceName: "synthetic-private-pin")
        source.selectedJSON = "expired"
        source.tokens["expired"] = "synthetic-private-token"
        source.expired.insert("expired")
        var diagnostics: [String] = []
        let provider = AnthropicUsageProvider(apiService: api, cliSource: source, activeProfileID: { profile.id },
                                             credentialDiagnostics: { diagnostics.append($0) })

        await assertFailure(.sessionKeyExpired) { try await provider.fetchUsage(for: profile) }
        let message = try XCTUnwrap(diagnostics.first)
        XCTAssertTrue(message.contains("savedCLI=true"))
        XCTAssertTrue(message.contains("usableJSONPresent=true"))
        XCTAssertTrue(message.contains("tokenPresent=true"))
        XCTAssertTrue(message.contains("expired=true"))
        XCTAssertTrue(message.contains("pinned=true"))
        XCTAssertTrue(message.contains("active=true"))
        XCTAssertFalse(message.contains(profile.id.uuidString))
        XCTAssertFalse(message.contains("synthetic-private"))
        XCTAssertFalse(message.contains("expired=" + "expired"))
    }

    private func makeProvider(_ api: SyntheticAnthropicAPI, _ source: SyntheticAnthropicCLI, activeID: UUID?) -> AnthropicUsageProvider {
        AnthropicUsageProvider(apiService: api, cliSource: source, activeProfileID: { activeID }, credentialDiagnostics: { _ in })
    }

    private func assertFailure(_ code: ErrorCode, operation: () async throws -> ClaudeUsage) async {
        do {
            _ = try await operation()
            XCTFail("A failed credential selection must throw instead of reporting cached usage as fresh")
        } catch let error as AppError {
            XCTAssertEqual(error.code, code)
        } catch {
            XCTFail("Expected a classified AppError")
        }
    }
}

@MainActor
private final class SyntheticAnthropicAPI: ClaudeAPIService {
    var oauthTokens: [String] = []
    var sessionOrganizations: [String] = []
    var organizationSessionKeys: [String?] = []
    var browserSessionKeys: [String] = []
    var organizations = [ClaudeAPIService.AccountInfo(uuid: "synthetic-org-A", name: "Synthetic A", capabilities: [])]
    var syntheticActiveProfile: Profile?
    var activeOrganizationHelperCount = 0
    var events: [String] = []
    var genericFetchCount = 0
    override func fetchUsageData() async throws -> ClaudeUsage { genericFetchCount += 1; return .empty }
    override func fetchUsageData(oauthAccessToken: String) async throws -> ClaudeUsage { oauthTokens.append(oauthAccessToken); return .empty }
    override func fetchOrganizationId(sessionKey: String? = nil) async throws -> String {
        activeOrganizationHelperCount += 1
        events.append("active-organization-helper")
        return syntheticActiveProfile?.organizationId ?? "synthetic-org-B"
    }
    override func fetchAllOrganizations(sessionKey: String? = nil) async throws -> [ClaudeAPIService.AccountInfo] {
        organizationSessionKeys.append(sessionKey)
        events.append("all-organizations")
        return organizations
    }
    override func fetchUsageData(sessionKey: String, organizationId: String) async throws -> ClaudeUsage {
        events.append("browser-usage"); browserSessionKeys.append(sessionKey); sessionOrganizations.append(organizationId); return .empty
    }
}

@MainActor
private final class SyntheticAnthropicCLI: AnthropicCLICredentialSource {
    var selectedJSON: String?
    var systemJSON: String?
    var systemAccount: String?
    var tokens: [String: String] = [:]
    var refreshTokens: [String: String] = [:]
    var expired: Set<String> = []
    var selectedIDs: [UUID] = []
    var allowRotationValues: [Bool] = []
    var systemReadCount = 0
    func ensureFreshCredentials(for profileId: UUID, allowRotation: Bool) async -> String? {
        selectedIDs.append(profileId); allowRotationValues.append(allowRotation); return selectedJSON
    }
    func readSystemCredentials() throws -> String? { systemReadCount += 1; return systemJSON }
    func readOAuthAccount() -> String? { systemAccount }
    func accountIdentity(fromOAuthAccountJSON json: String?) -> String? { json }
    func extractAccessToken(from jsonData: String) -> String? { tokens[jsonData] }
    func extractRefreshToken(from jsonData: String) -> String? { refreshTokens[jsonData] }
    func isTokenExpired(_ jsonData: String) -> Bool { expired.contains(jsonData) }
    func hasUsableSystemCredentials() -> Bool { systemJSON != nil }
}
