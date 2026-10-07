import XCTest
@testable import Claude_Usage

/// Uses only synthetic auth.json files and an injected usage transport/profile
/// context. No application startup, login store, shared auth file or network.
@MainActor
final class CodexAccountBindingTests: XCTestCase {
    private var directory: URL!
    private var authURL: URL!
    private var profiles: [Profile] = []
    private var activeID: UUID?
    private var requestCount = 0
    private var saveCount = 0
    private var allowSave = true
    private var requestFailure: AppError?
    private var afterRequest: (() throws -> Void)?

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        authURL = directory.appendingPathComponent("auth.json")
        try writeAuth(accountID: "account-a")
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func writeAuth(accountID: String?) throws {
        var tokens = ["access_token": "synthetic-access", "refresh_token": "synthetic-refresh"]
        tokens["account_id"] = accountID
        try JSONSerialization.data(withJSONObject: ["tokens": tokens]).write(to: authURL)
    }

    private func makeProvider() -> CodexUsageProvider {
        CodexUsageProvider(
            authService: CodexAuthService(authFileURL: authURL),
            requestUsage: { [self] _ in
                requestCount += 1
                try afterRequest?()
                if let requestFailure { throw requestFailure }
                return try JSONDecoder().decode(CodexUsageResponse.self, from: Data("{\"plan_type\":\"plus\"}".utf8))
            },
            profileContext: { [self] in (activeID, profiles) },
            saveProfile: { [self] updated in
                saveCount += 1
                guard allowSave, let index = profiles.firstIndex(where: { $0.id == updated.id }) else { return false }
                profiles[index] = updated
                return true
            }
        )
    }

    private func install(_ profile: Profile, active: Bool) {
        profiles = [profile]
        activeID = active ? profile.id : UUID()
    }

    private func expectFailure(_ provider: CodexUsageProvider, profile: Profile,
                               code: ErrorCode = .providerCredentialsNotFound) async {
        do {
            _ = try await provider.fetchUsage(for: profile)
            XCTFail("Expected a recoverable failure")
        } catch let error as AppError {
            XCTAssertEqual(error.code, code)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testSuccessfulActiveFileConnectionBindsOnlyThatProfile() async throws {
        let profile = Profile(name: "Active", provider: .codex)
        let other = Profile(name: "Unbound", provider: .codex)
        profiles = [profile, other]
        activeID = profile.id
        _ = try await makeProvider().fetchUsage(for: profile)
        XCTAssertEqual(profiles[0].codexAccountID, "account-a")
        XCTAssertNil(profiles[1].codexAccountID)
        XCTAssertEqual(saveCount, 1)
    }

    func testBoundFileProfileCanFetchWhileAnotherProviderIsActive() async throws {
        let profile = Profile(name: "Bound", provider: .codex, codexAccountID: "account-a")
        install(profile, active: false)
        _ = try await makeProvider().fetchUsage(for: profile)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(saveCount, 0)
    }

    func testUnboundInactiveFileProfileIsRejectedBeforeRequest() async throws {
        let profile = Profile(name: "Unbound", provider: .codex)
        install(profile, active: false)
        await expectFailure(makeProvider(), profile: profile)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(saveCount, 0)
    }

    func testAccountMismatchIsRejectedEvenForActiveProfile() async throws {
        let profile = Profile(name: "Bound", provider: .codex, codexAccountID: "account-b")
        install(profile, active: true)
        await expectFailure(makeProvider(), profile: profile)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(profiles[0].codexAccountID, "account-b")
    }

    func testMissingAccountIdentityCannotBindOrFetchSharedFile() async throws {
        try writeAuth(accountID: nil)
        let profile = Profile(name: "Unknown", provider: .codex)
        install(profile, active: true)
        await expectFailure(makeProvider(), profile: profile)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(saveCount, 0)
    }

    func testFailedUsageRequestDoesNotBind() async throws {
        let profile = Profile(name: "Active", provider: .codex)
        install(profile, active: true)
        requestFailure = AppError(code: .providerCredentialsNotFound, message: "Synthetic failure", isRecoverable: true)
        await expectFailure(makeProvider(), profile: profile)
        XCTAssertNil(profiles[0].codexAccountID)
        XCTAssertEqual(saveCount, 0)
    }

    func testAccountChangeDuringAuthRetryIsRejectedBeforeSecondRequest() async throws {
        let profile = Profile(name: "Bound", provider: .codex, codexAccountID: "account-a")
        install(profile, active: false)
        afterRequest = { [self] in try writeAuth(accountID: "account-b") }
        requestFailure = AppError(code: .providerAuthExpired, message: "Synthetic expiry", isRecoverable: true)
        await expectFailure(makeProvider(), profile: profile)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(saveCount, 0)
    }

    func testSwitchingActiveProfileDuringFirstConnectionDoesNotBind() async throws {
        let profile = Profile(name: "Active", provider: .codex)
        install(profile, active: true)
        afterRequest = { [self] in activeID = UUID() }
        await expectFailure(makeProvider(), profile: profile)
        XCTAssertNil(profiles[0].codexAccountID)
        XCTAssertEqual(saveCount, 0)
    }

    func testChangedCredentialSourceDuringRequestDoesNotOverwriteProfile() async throws {
        let profile = Profile(name: "Active", provider: .codex)
        install(profile, active: true)
        afterRequest = { [self] in profiles[0].codexCredentialsJSON = "{}" }
        await expectFailure(makeProvider(), profile: profile)
        XCTAssertEqual(profiles[0].codexCredentialsJSON, "{}")
        XCTAssertNil(profiles[0].codexAccountID)
        XCTAssertEqual(saveCount, 0)
    }

    func testChangedAccountBindingDuringRequestIsNotOverwritten() async throws {
        let profile = Profile(name: "Active", provider: .codex)
        install(profile, active: true)
        afterRequest = { [self] in profiles[0].codexAccountID = "account-b" }
        await expectFailure(makeProvider(), profile: profile)
        XCTAssertEqual(profiles[0].codexAccountID, "account-b")
        XCTAssertEqual(saveCount, 0)
    }

    func testBindingPersistenceFailureIsSurfaced() async throws {
        let profile = Profile(name: "Active", provider: .codex)
        install(profile, active: true)
        allowSave = false
        await expectFailure(makeProvider(), profile: profile, code: .storageWriteFailed)
        XCTAssertNil(profiles[0].codexAccountID)
    }

    func testManualProfileDoesNotUseFileBindingOrActiveProfileRule() async throws {
        let profile = Profile(name: "Manual", provider: .codex,
                              codexCredentialsJSON: "{\"OPENAI_API_KEY\":\"synthetic-api-key\"}",
                              codexAccountID: "previous-file-account")
        install(profile, active: false)
        _ = try await makeProvider().fetchUsage(for: profile)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(profiles[0].codexAccountID, "previous-file-account")
    }

    func testNonsecretBindingRoundTripsWithoutCredentials() throws {
        let profile = Profile(name: "Bound", provider: .codex,
                              codexCredentialsJSON: "secret-synthetic-json", codexAccountID: "account-a")
        let data = try JSONEncoder().encode(profile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["codexAccountID"] as? String, "account-a")
        XCTAssertNil(object["codexCredentialsJSON"])
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: data).codexAccountID, "account-a")
    }

    func testLegacyProfileDecodesWithoutBinding() throws {
        let json = "{\"id\":\"\(UUID().uuidString)\",\"name\":\"Legacy\",\"provider\":\"codex\"}"
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertNil(profile.codexAccountID)
    }
}
