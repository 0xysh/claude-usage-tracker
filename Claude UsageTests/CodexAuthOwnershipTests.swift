import XCTest
@testable import Claude_Usage

/// The Codex process owns refresh-token rotation for shared auth.json files.
/// Every fixture is synthetic and every request is intercepted in memory.
@MainActor
final class CodexAuthOwnershipTests: XCTestCase {
    private var directory: URL!
    private var authURL: URL!
    private var session: URLSession!
    private var service: CodexAuthService!
    private var profiles: [Profile] = []
    private var allowSave = true

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAuthOwnershipTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        authURL = directory.appendingPathComponent("auth.json")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexAuthOwnershipProtocol.self]
        session = URLSession(configuration: configuration)
        service = CodexAuthService(authFileURL: authURL, session: session,
                                   profileContext: { [self] in profiles },
                                   saveProfile: { [self] updated in
            guard allowSave, let index = profiles.firstIndex(where: { $0.id == updated.id }) else { return false }
            profiles[index] = updated
            return true
        })
        CodexAuthOwnershipProtocol.reset()
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        try FileManager.default.removeItem(at: directory)
        service = nil
        session = nil
    }

    func testStaleFileCredentialsAreReadWithoutRefreshingOrWriting() async throws {
        let original = try writeAuth(accessToken: "file-access", refreshToken: "file-refresh")
        let profile = Profile(name: "File account", provider: .codex)
        let cached = try service.loadCredentials(for: profile)

        let result = try await service.refreshIfNeeded(cached, for: profile)

        XCTAssertEqual(result.accessToken, "file-access")
        XCTAssertEqual(result.refreshToken, "file-refresh")
        XCTAssertEqual(CodexAuthOwnershipProtocol.requests.count, 0)
        XCTAssertEqual(try Data(contentsOf: authURL), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["auth.json"])
    }

    func testForcedRefreshReloadsCodexRotationWithoutRotatingItAgain() async throws {
        let profile = Profile(name: "File account", provider: .codex)
        _ = try writeAuth(accessToken: "before-access", refreshToken: "before-refresh")
        let cached = try service.loadCredentials(for: profile)
        let rotated = try writeAuth(accessToken: "codex-rotated-access", refreshToken: "codex-rotated-refresh")

        let result = try await service.refreshIfNeeded(cached, for: profile, force: true)

        XCTAssertEqual(result.accessToken, "codex-rotated-access")
        XCTAssertEqual(result.refreshToken, "codex-rotated-refresh")
        XCTAssertEqual(CodexAuthOwnershipProtocol.requests.count, 0)
        XCTAssertEqual(try Data(contentsOf: authURL), rotated)
    }

    func testFreshCachedCredentialsStillReloadCurrentFile() async throws {
        let profile = Profile(name: "File account", provider: .codex)
        _ = try writeAuth(accessToken: "cached-access", refreshToken: "cached-refresh", refreshedAt: Date())
        let cached = try service.loadCredentials(for: profile)
        _ = try writeAuth(accessToken: "current-access", refreshToken: "current-refresh", refreshedAt: Date())

        let result = try await service.refreshIfNeeded(cached, for: profile)

        XCTAssertEqual(result.accessToken, "current-access")
        XCTAssertEqual(CodexAuthOwnershipProtocol.requests.count, 0)
    }

    func testRemovedFileDoesNotUseCachedCredentialsOrAttemptRefresh() async throws {
        let profile = Profile(name: "File account", provider: .codex)
        _ = try writeAuth(accessToken: "cached-access", refreshToken: "cached-refresh", refreshedAt: Date())
        let cached = try service.loadCredentials(for: profile)
        try FileManager.default.removeItem(at: authURL)

        do {
            _ = try await service.refreshIfNeeded(cached, for: profile)
            XCTFail("A removed Codex login must be surfaced rather than reusing its cached credentials")
        } catch let error as AppError {
            XCTAssertEqual(error.code, .providerCredentialsNotFound)
        }
        XCTAssertEqual(CodexAuthOwnershipProtocol.requests.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: authURL.path))
    }

    func testManualCredentialsKeepTheirRefreshFlowWithoutChangingSharedFile() async throws {
        let original = try writeAuth(accessToken: "unrelated-file-access", refreshToken: "unrelated-file-refresh")
        let manual = """
        {"tokens":{"access_token":"manual-access","refresh_token":"manual-refresh","account_id":"manual-account"}}
        """
        let profile = Profile(name: "Manual account", provider: .codex, codexCredentialsJSON: manual)
        profiles = [profile]
        let credentials = try service.loadCredentials(for: profile)

        let refreshed = try await service.refreshIfNeeded(credentials, for: profile)

        XCTAssertEqual(refreshed.accessToken, "server-refreshed-access")
        XCTAssertEqual(refreshed.refreshToken, "server-refreshed-refresh")
        XCTAssertEqual(refreshed.accountId, "manual-account")
        XCTAssertNotNil(refreshed.lastRefresh)
        let requests = CodexAuthOwnershipProtocol.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(try Data(contentsOf: authURL), original)
    }

    func testFreshManualCredentialsDoNotReadMissingFileOrRefresh() async throws {
        let manual = """
        {"tokens":{"access_token":"manual-access","refresh_token":"manual-refresh"},"last_refresh":"\(ISO8601DateFormatter().string(from: Date()))"}
        """
        let profile = Profile(name: "Manual account", provider: .codex, codexCredentialsJSON: manual)
        let credentials = try service.loadCredentials(for: profile)

        let unchanged = try await service.refreshIfNeeded(credentials, for: profile)

        XCTAssertEqual(unchanged.accessToken, "manual-access")
        XCTAssertEqual(CodexAuthOwnershipProtocol.requests.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: authURL.path))
    }

    private func manualProfile(_ name: String = "Manual") -> Profile {
        Profile(name: name, provider: .codex, codexCredentialsJSON: """
        {"tokens":{"access_token":"manual-access","refresh_token":"manual-refresh","account_id":"manual-account"}}
        """)
    }

    func testJoinedRefreshPersistsRotatedCredentialsToEveryMatchingProfile() async throws {
        let first = manualProfile("First")
        let second = manualProfile("Second")
        profiles = [first, second]
        CodexAuthOwnershipProtocol.holdResponses = true
        let firstCredentials = try service.loadCredentials(for: first)
        let secondCredentials = try service.loadCredentials(for: second)
        async let firstResult = service.refreshIfNeeded(firstCredentials, for: first)
        async let secondResult = service.refreshIfNeeded(secondCredentials, for: second)
        await waitForRequest()
        CodexAuthOwnershipProtocol.releaseResponses()
        _ = try await (firstResult, secondResult)
        await Task.yield()

        XCTAssertEqual(CodexAuthOwnershipProtocol.requests.count, 1)
        for profile in profiles {
            let stored = try XCTUnwrap(CodexAuthService.parse(Data(try XCTUnwrap(profile.codexCredentialsJSON).utf8)))
            XCTAssertEqual(stored.accessToken, "server-refreshed-access")
            XCTAssertEqual(stored.refreshToken, "server-refreshed-refresh")
        }
    }

    func testReplacedManualCredentialsAreNotOverwrittenByAnObsoleteRefresh() async throws {
        let profile = manualProfile()
        profiles = [profile]
        CodexAuthOwnershipProtocol.holdResponses = true
        let credentials = try service.loadCredentials(for: profile)
        let operation = Task { try await service.refreshIfNeeded(credentials, for: profile) }
        await waitForRequest()
        let replacement = "{\"tokens\":{\"access_token\":\"replacement-access\",\"refresh_token\":\"replacement-refresh\"}}"
        profiles[0].codexCredentialsJSON = replacement
        CodexAuthOwnershipProtocol.releaseResponses()
        do { _ = try await operation.value } catch { /* Obsolete completion may fail safely. */ }
        await Task.yield()
        XCTAssertEqual(profiles[0].codexCredentialsJSON, replacement)
    }

    func testChangedSourceToSharedFileIsNotOverwrittenByAnObsoleteManualRefresh() async throws {
        let profile = manualProfile()
        profiles = [profile]
        CodexAuthOwnershipProtocol.holdResponses = true
        let credentials = try service.loadCredentials(for: profile)
        let operation = Task { try await service.refreshIfNeeded(credentials, for: profile) }
        await waitForRequest()
        profiles[0].codexCredentialsJSON = nil
        CodexAuthOwnershipProtocol.releaseResponses()
        do { _ = try await operation.value } catch { /* Obsolete completion may fail safely. */ }
        await Task.yield()
        XCTAssertNil(profiles[0].codexCredentialsJSON)
    }

    func testManualRefreshReportsSecurePersistenceFailure() async throws {
        let profile = manualProfile()
        profiles = [profile]
        allowSave = false
        let credentials = try service.loadCredentials(for: profile)
        do {
            _ = try await service.refreshIfNeeded(credentials, for: profile)
            XCTFail("A successful token rotation must not hide failed secure persistence")
        } catch let error as AppError {
            XCTAssertEqual(error.code, .storageWriteFailed)
        }
        XCTAssertEqual(profiles[0].codexCredentialsJSON, profile.codexCredentialsJSON)
    }

    private func waitForRequest() async {
        let deadline = Date().addingTimeInterval(2)
        while CodexAuthOwnershipProtocol.requests.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(CodexAuthOwnershipProtocol.requests.count, 1, "The synthetic refresh must reach the held transport")
        // Give both main-actor callers a chance to join the held task.
        await Task.yield()
    }

    private func writeAuth(accessToken: String, refreshToken: String, refreshedAt: Date? = nil) throws -> Data {
        var json: [String: Any] = [
            "tokens": ["access_token": accessToken, "refresh_token": refreshToken],
            "future_metadata": ["owned_by": "codex"],
        ]
        if let refreshedAt {
            json["last_refresh"] = ISO8601DateFormatter().string(from: refreshedAt)
        }
        let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try bytes.write(to: authURL)
        return bytes
    }
}

private final class CodexAuthOwnershipProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var capturedRequests: [URLRequest] = []
    private static var pendingResponses: [CodexAuthOwnershipProtocol] = []
    private static var shouldHoldResponses = false

    static var holdResponses: Bool {
        get { lock.lock(); defer { lock.unlock() }; return shouldHoldResponses }
        set { lock.lock(); defer { lock.unlock() }; shouldHoldResponses = newValue }
    }

    static func releaseResponses() {
        lock.lock()
        let pending = pendingResponses
        pendingResponses = []
        shouldHoldResponses = false
        lock.unlock()
        pending.forEach { $0.completeResponse() }
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests = []
        pendingResponses = []
        shouldHoldResponses = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        if Self.shouldHoldResponses {
            Self.pendingResponses.append(self)
            Self.lock.unlock()
            return
        }
        Self.lock.unlock()

        completeResponse()
    }

    private func completeResponse() {
        let data = Data("{\"access_token\":\"server-refreshed-access\",\"refresh_token\":\"server-refreshed-refresh\",\"id_token\":\"synthetic-id\"}".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
