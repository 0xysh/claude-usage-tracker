import XCTest
@testable import Claude_Usage

/// Uses injected stores and an isolated defaults suite; never accesses Keychain
/// or the application's real profile preferences.
@MainActor
final class ProfileStoreSecurityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            suite = "ProfileStoreSecurityTests." + UUID().uuidString
            defaults = UserDefaults(suiteName: suite)!
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            defaults.removePersistentDomain(forName: suite)
            defaults = nil
            suite = nil
        }
        try await super.tearDown()
    }

    func testNewSecureWriteFailureKeepsAttemptInMemoryWithoutPlaintextDocument() async throws {
        let fixture = Fixture(defaults: defaults)
        fixture.snapshots.rejectWrites = true
        let profile = syntheticProfile()

        XCTAssertFalse(fixture.store.saveProfiles([profile]))
        XCTAssertNil(fixture.document.data)
        XCTAssertEqual(fixture.store.lastPersistenceError, .secureWriteFailed)
        XCTAssertEqual(fixture.store.loadProfiles(), [profile])
    }

    func testFailedCredentialUpdatePreservesDurableOriginalAndPendingEdit() async throws {
        let fixture = Fixture(defaults: defaults)
        let original = syntheticProfile()
        XCTAssertTrue(fixture.store.saveProfiles([original]))
        let bytes = fixture.document.data
        let snapshots = fixture.snapshots.values
        fixture.snapshots.rejectWrites = true
        var changed = original
        changed.claudeSessionKey = "synthetic-replacement"

        XCTAssertFalse(fixture.store.saveProfiles([changed]))
        XCTAssertEqual(fixture.store.loadProfiles(), [changed])
        XCTAssertEqual(fixture.document.data, bytes)
        XCTAssertEqual(fixture.snapshots.values, snapshots)
        XCTAssertEqual(fixture.freshStore().loadProfiles(), [original])
        fixture.snapshots.rejectWrites = false
        XCTAssertTrue(fixture.store.saveProfiles(fixture.store.loadProfiles()))
        XCTAssertEqual(fixture.freshStore().loadProfiles(), [changed])
        XCTAssertNil(fixture.store.lastPersistenceError)
    }

    func testFailedDeletionCannotDeleteOriginalCredentials() async throws {
        let fixture = Fixture(defaults: defaults)
        let original = syntheticProfile()
        XCTAssertTrue(fixture.store.saveProfiles([original]))
        let bytes = fixture.document.data
        fixture.snapshots.rejectWrites = true

        XCTAssertFalse(fixture.store.saveProfiles([]))
        fixture.store.deleteProfileSecrets(original.id)
        XCTAssertEqual(fixture.document.data, bytes)
        XCTAssertEqual(fixture.store.loadProfiles(), [])
        XCTAssertEqual(fixture.freshStore().loadProfiles(), [original])
        XCTAssertTrue(fixture.legacy.deletedIDs.isEmpty)
    }

    func testLegacyMigrationCommitsAllFourSecretsThenCleansLegacyKeys() async throws {
        let fixture = Fixture(defaults: defaults)
        let profile = syntheticProfile()
        let encoder = JSONEncoder()
        encoder.userInfo[Profile.includeSecretsKey] = true
        fixture.document.data = try encoder.encode([profile])

        XCTAssertEqual(fixture.store.loadProfiles(), [profile])
        let document = String(decoding: try XCTUnwrap(fixture.document.data), as: UTF8.self)
        for secret in [profile.claudeSessionKey, profile.apiSessionKey, profile.cliCredentialsJSON, profile.codexCredentialsJSON].compactMap({ $0 }) {
            XCTAssertFalse(document.contains(secret))
        }
        XCTAssertEqual(fixture.legacy.deletedIDs, [profile.id])
        XCTAssertEqual(fixture.freshStore().loadProfiles(), [profile])
    }

    func testFailedLegacyMigrationPreservesExactOriginalBytesAndKeys() async throws {
        let fixture = Fixture(defaults: defaults)
        let profile = syntheticProfile()
        let encoder = JSONEncoder()
        encoder.userInfo[Profile.includeSecretsKey] = true
        let original = try encoder.encode([profile])
        fixture.document.data = original
        fixture.snapshots.rejectWrites = true

        XCTAssertEqual(fixture.store.loadProfiles(), [profile])
        XCTAssertEqual(fixture.document.data, original)
        XCTAssertTrue(fixture.legacy.deletedIDs.isEmpty)
        XCTAssertEqual(fixture.store.lastPersistenceError, .secureWriteFailed)
    }

    func testLegacyCanonicalKeychainSecretsMigrateThroughSyntheticReader() async throws {
        let fixture = Fixture(defaults: defaults)
        let profile = Profile(name: "Synthetic Canonical Legacy")
        fixture.document.data = try JSONEncoder().encode([profile])
        fixture.legacy.values[.claudeSessionKey] = "synthetic-canonical-claude"
        fixture.legacy.values[.apiSessionKey] = "synthetic-canonical-api"
        fixture.legacy.values[.cliCredentialsJSON] = "synthetic-canonical-cli"
        fixture.legacy.values[.codexCredentialsJSON] = "synthetic-canonical-codex"

        let migrated = try XCTUnwrap(fixture.store.loadProfiles().first)
        XCTAssertEqual(migrated.claudeSessionKey, "synthetic-canonical-claude")
        XCTAssertEqual(migrated.apiSessionKey, "synthetic-canonical-api")
        XCTAssertEqual(migrated.cliCredentialsJSON, "synthetic-canonical-cli")
        XCTAssertEqual(migrated.codexCredentialsJSON, "synthetic-canonical-codex")
        XCTAssertEqual(fixture.legacy.deletedIDs, [profile.id])
        fixture.legacy.values.removeAll()
        XCTAssertEqual(fixture.freshStore().loadProfiles(), [migrated])
    }

    func testDeniedLegacyReadCannotScrubOrOverwriteOriginal() async throws {
        let fixture = Fixture(defaults: defaults)
        let profile = Profile(name: "Synthetic Legacy")
        let original = try JSONEncoder().encode([profile])
        fixture.document.data = original
        fixture.legacy.rejectReads = true

        XCTAssertTrue(fixture.store.loadProfiles().isEmpty)
        XCTAssertEqual(fixture.store.lastPersistenceError, .secureReadFailed)
        XCTAssertFalse(fixture.store.saveProfiles([Profile(name: "Replacement")]))
        XCTAssertEqual(fixture.document.data, original)
        XCTAssertTrue(fixture.legacy.deletedIDs.isEmpty)
        XCTAssertTrue(fixture.snapshots.values.isEmpty)
    }

    func testMalformedReferencedSnapshotCannotBecomeEmptyCredentialOverwrite() async throws {
        let fixture = Fixture(defaults: defaults)
        XCTAssertTrue(fixture.store.saveProfiles([syntheticProfile()]))
        let original = fixture.document.data
        for id in fixture.snapshots.values.keys {
            fixture.snapshots.values[id] = Data("malformed-synthetic-snapshot".utf8)
        }

        XCTAssertTrue(fixture.store.loadProfiles().isEmpty)
        XCTAssertEqual(fixture.store.lastPersistenceError, .secureReadFailed)
        XCTAssertFalse(fixture.store.saveProfiles([Profile(name: "Default")]))
        XCTAssertEqual(fixture.document.data, original)
    }

    func testCredentialHelperThrowsOnFailureWhileRetainingAttemptedEdit() async throws {
        let fixture = Fixture(defaults: defaults)
        let original = syntheticProfile()
        XCTAssertTrue(fixture.store.saveProfiles([original]))
        fixture.snapshots.rejectWrites = true
        let credentials = ProfileCredentials(claudeSessionKey: "synthetic-attempt", organizationId: "synthetic-org")

        XCTAssertThrowsError(try fixture.store.saveProfileCredentials(original.id, credentials: credentials)) { error in
            XCTAssertEqual(error as? SecureProfilePersistenceError, .secureWriteFailed)
        }
        XCTAssertEqual(fixture.store.loadProfiles().first?.claudeSessionKey, "synthetic-attempt")
        XCTAssertEqual(fixture.freshStore().loadProfiles(), [original])
    }

    func testDurableMetadataFailureKeepsBothSnapshotsAndPendingProfile() async throws {
        let fixture = Fixture(defaults: defaults)
        let original = syntheticProfile()
        XCTAssertTrue(fixture.store.saveProfiles([original]))
        let originalIDs = Set(fixture.snapshots.values.keys)
        fixture.document.failDurableCommit = true
        var changed = original
        changed.codexCredentialsJSON = "synthetic-codex-replacement"

        XCTAssertFalse(fixture.store.saveProfiles([changed]))
        XCTAssertEqual(fixture.store.lastPersistenceError, .documentWriteFailed)
        XCTAssertEqual(fixture.store.loadProfiles(), [changed])
        XCTAssertTrue(originalIDs.isSubset(of: Set(fixture.snapshots.values.keys)))
        XCTAssertEqual(fixture.snapshots.values.count, 2)
    }

    private func syntheticProfile() -> Profile {
        Profile(name: "Synthetic Personal", claudeSessionKey: "synthetic-claude-secret",
                apiSessionKey: "synthetic-api-secret", cliCredentialsJSON: "synthetic-cli-secret",
                codexCredentialsJSON: "synthetic-codex-secret")
    }

    private struct Fixture {
        let defaults: UserDefaults
        let document = SyntheticProfileDocumentStore()
        let snapshots = SyntheticProfileSnapshotStore()
        let legacy = SyntheticLegacyProfileStore()
        let store: ProfileStore
        init(defaults: UserDefaults) {
            self.defaults = defaults
            store = ProfileStore(defaults: defaults, documentStorage: document, snapshotStorage: snapshots, legacySecrets: legacy)
        }
        func freshStore() -> ProfileStore {
            ProfileStore(defaults: defaults, documentStorage: document, snapshotStorage: snapshots, legacySecrets: legacy)
        }
    }
}

private final class SyntheticProfileDocumentStore: ProfileDocumentStorage {
    var data: Data?
    var failDurableCommit = false
    func readDocument() -> Data? { data }
    func writeDocument(_ data: Data) throws {
        self.data = data
        if failDurableCommit { throw SecureProfilePersistenceError.documentWriteFailed }
    }
}

private final class SyntheticProfileSnapshotStore: ProfileSnapshotStorage {
    var values: [UUID: Data] = [:]
    var rejectWrites = false
    func writeSnapshot(_ data: Data, id: UUID) -> Bool {
        guard !rejectWrites else { return false }
        values[id] = data
        return true
    }
    func readSnapshot(id: UUID) throws -> Data? { values[id] }
    func deleteSnapshot(id: UUID) -> Bool { values.removeValue(forKey: id); return true }
}

private final class SyntheticLegacyProfileStore: ProfileLegacySecretStorage {
    var rejectReads = false
    var values: [KeychainService.ProfileSecretField: String] = [:]
    var deletedIDs: [UUID] = []
    func readProfileSecret(profileId: UUID, field: KeychainService.ProfileSecretField) throws -> String? {
        if rejectReads { throw SecureProfilePersistenceError.secureReadFailed }
        return values[field]
    }
    func deleteAllProfileSecrets(profileId: UUID) { deletedIDs.append(profileId) }
}
