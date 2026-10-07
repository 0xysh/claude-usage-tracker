import XCTest
@testable import Claude_Usage

@MainActor
final class SecureProfilePersistenceTests: XCTestCase {
    private let credentials = Data("synthetic-credential-snapshot".utf8)

    func testSuccessfulCommitKeepsSecretsOutOfProfileDocument() async throws {
        let document = MemoryProfileDocumentStorage()
        let snapshots = MemoryProfileSnapshotStorage()
        let store = SecureProfilePersistence<[SyntheticStoredProfile]>(documentStorage: document, snapshotStorage: snapshots)
        try store.save([SyntheticStoredProfile(name: "Personal", secret: "synthetic-secret")], credentials: credentials)

        XCTAssertFalse(String(decoding: try XCTUnwrap(document.data), as: UTF8.self).contains("synthetic-secret"))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.profiles.first?.name, "Personal")
        XCTAssertEqual(loaded.credentials, credentials)
        XCTAssertFalse(loaded.isLegacy)
    }

    func testSecureWriteFailurePreservesPreviousDocumentAndSnapshot() async throws {
        let (store, document, snapshots) = try committedStore()
        let previous = document.data
        let previousIDs = Set(snapshots.values.keys)
        snapshots.rejectWrites = true

        XCTAssertThrowsError(try store.save([SyntheticStoredProfile(name: "Changed")], credentials: Data("replacement".utf8)))
        XCTAssertEqual(document.data, previous)
        XCTAssertEqual(Set(snapshots.values.keys), previousIDs)
        XCTAssertEqual(try store.load()?.profiles.first?.name, "Original")
    }

    func testSecureReadbackMismatchCannotCommitOrDeletePreviousSnapshot() async throws {
        let (store, document, snapshots) = try committedStore()
        let previous = document.data
        let previousIDs = Set(snapshots.values.keys)
        snapshots.corruptNewReadback = true

        XCTAssertThrowsError(try store.save([SyntheticStoredProfile(name: "Changed")], credentials: Data("replacement".utf8)))
        XCTAssertEqual(document.data, previous)
        XCTAssertTrue(previousIDs.isSubset(of: Set(snapshots.values.keys)))
    }

    func testFailedDocumentReadbackKeepsBothRecoverableSnapshots() async throws {
        let (store, document, snapshots) = try committedStore()
        let previous = document.data
        let previousIDs = Set(snapshots.values.keys)
        document.rejectWrites = true

        XCTAssertThrowsError(try store.save([SyntheticStoredProfile(name: "Changed")], credentials: Data("replacement".utf8)))
        XCTAssertEqual(document.data, previous)
        XCTAssertTrue(previousIDs.isSubset(of: Set(snapshots.values.keys)))
        XCTAssertEqual(snapshots.values.count, 2, "Do not delete a staged snapshot when a metadata write has an uncertain outcome")
    }

    func testFailedDurableDocumentCommitRetainsBothSnapshotsEvenIfCachedReadbackMatches() async throws {
        let (store, document, snapshots) = try committedStore()
        let previousIDs = Set(snapshots.values.keys)
        document.failDurableCommit = true

        XCTAssertThrowsError(try store.save([SyntheticStoredProfile(name: "Changed")], credentials: Data("replacement".utf8))) { error in
            XCTAssertEqual(error as? SecureProfilePersistenceError, .documentWriteFailed)
        }
        XCTAssertTrue(previousIDs.isSubset(of: Set(snapshots.values.keys)))
        XCTAssertEqual(snapshots.values.count, 2)
    }

    func testUnchangedCredentialsReuseSecureSnapshotForMetadataUpdates() async throws {
        let (store, document, snapshots) = try committedStore()
        let writeCount = snapshots.writeCount
        try store.save([SyntheticStoredProfile(name: "Renamed")], credentials: credentials)

        XCTAssertEqual(snapshots.writeCount, writeCount)
        XCTAssertEqual(snapshots.values.count, 1)
        XCTAssertNotNil(document.data)
        XCTAssertEqual(try store.load()?.profiles.first?.name, "Renamed")
    }

    func testLegacyLoadDoesNotModifyExistingPlaintextDocument() async throws {
        let document = MemoryProfileDocumentStorage()
        let legacy = Data("[{\"name\":\"Legacy\",\"secret\":\"synthetic-legacy-secret\"}]".utf8)
        document.data = legacy
        let snapshots = MemoryProfileSnapshotStorage()
        let store = SecureProfilePersistence<[SyntheticStoredProfile]>(documentStorage: document, snapshotStorage: snapshots)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertTrue(loaded.isLegacy)
        XCTAssertNotNil(loaded.profiles.first?.secret)
        XCTAssertEqual(document.data, legacy)
        XCTAssertEqual(document.writeCount, 0)
        XCTAssertEqual(snapshots.writeCount, 0)
    }

    func testLegacyPlaintextScrubOccursOnlyAfterVerifiedSecureCommit() async throws {
        let document = MemoryProfileDocumentStorage()
        document.data = Data("[{\"name\":\"Legacy\",\"secret\":\"synthetic-legacy-secret\"}]".utf8)
        let snapshots = MemoryProfileSnapshotStorage()
        let store = SecureProfilePersistence<[SyntheticStoredProfile]>(documentStorage: document, snapshotStorage: snapshots)
        let legacy = try XCTUnwrap(store.load())
        try store.save(legacy.profiles, credentials: credentials)

        XCTAssertFalse(String(decoding: try XCTUnwrap(document.data), as: UTF8.self).contains("synthetic-legacy-secret"))
        XCTAssertEqual(try store.load()?.credentials, credentials)
        XCTAssertFalse(try XCTUnwrap(store.load()).isLegacy)
    }

    func testFailedLegacyMigrationPreservesOriginalBytesForRecovery() async throws {
        let document = MemoryProfileDocumentStorage()
        let legacy = Data("[{\"name\":\"Legacy\",\"secret\":\"synthetic-legacy-secret\"}]".utf8)
        document.data = legacy
        let snapshots = MemoryProfileSnapshotStorage()
        snapshots.rejectWrites = true
        let store = SecureProfilePersistence<[SyntheticStoredProfile]>(documentStorage: document, snapshotStorage: snapshots)
        let loaded = try XCTUnwrap(store.load())

        XCTAssertThrowsError(try store.save(loaded.profiles, credentials: credentials))
        XCTAssertEqual(document.data, legacy)
        XCTAssertEqual(document.writeCount, 0)
    }

    func testUnreadableSecureSnapshotCannotBecomeAnEmptyCredentialOverwrite() async throws {
        let (_, document, snapshots) = try committedStore()
        let previous = document.data
        snapshots.rejectReads = true
        let reloaded = SecureProfilePersistence<[SyntheticStoredProfile]>(documentStorage: document, snapshotStorage: snapshots)

        XCTAssertThrowsError(try reloaded.load())
        XCTAssertThrowsError(try reloaded.save([SyntheticStoredProfile(name: "Default")], credentials: Data()))
        XCTAssertEqual(document.data, previous)
        snapshots.rejectReads = false
        XCTAssertEqual(try reloaded.load()?.profiles.first?.name, "Original")
    }

    func testMissingReferencedSnapshotCannotOverwriteProfiles() async throws {
        let (_, document, snapshots) = try committedStore()
        let previous = document.data
        snapshots.values.removeAll()
        let reloaded = SecureProfilePersistence<[SyntheticStoredProfile]>(documentStorage: document, snapshotStorage: snapshots)

        XCTAssertThrowsError(try reloaded.save([], credentials: Data()))
        XCTAssertEqual(document.data, previous)
    }

    func testSameInstanceDoesNotTrustCachedSnapshotAfterExternalDeletion() async throws {
        let (store, document, snapshots) = try committedStore()
        let previous = document.data
        snapshots.values.removeAll()

        XCTAssertThrowsError(try store.save([SyntheticStoredProfile(name: "Renamed")], credentials: credentials))
        XCTAssertEqual(document.data, previous)
        XCTAssertEqual(snapshots.writeCount, 1)
    }

    func testSameInstanceDoesNotTrustCachedSnapshotWhenSecureReadsFail() async throws {
        let (store, document, snapshots) = try committedStore()
        let previous = document.data
        snapshots.rejectReads = true

        XCTAssertThrowsError(try store.save([SyntheticStoredProfile(name: "Renamed")], credentials: credentials))
        XCTAssertEqual(document.data, previous)
        XCTAssertEqual(snapshots.writeCount, 1)
    }

    func testFailedDeletionPreservesDurableProfileAndCredentials() async throws {
        let (store, document, snapshots) = try committedStore()
        let previous = document.data
        snapshots.rejectWrites = true

        XCTAssertThrowsError(try store.save([], credentials: Data("empty-snapshot".utf8)))
        XCTAssertEqual(document.data, previous)
        XCTAssertEqual(try store.load()?.profiles.first?.name, "Original")
        XCTAssertEqual(try store.load()?.credentials, credentials)
    }

    private func committedStore() throws -> (SecureProfilePersistence<[SyntheticStoredProfile]>, MemoryProfileDocumentStorage, MemoryProfileSnapshotStorage) {
        let document = MemoryProfileDocumentStorage()
        let snapshots = MemoryProfileSnapshotStorage()
        let store = SecureProfilePersistence<[SyntheticStoredProfile]>(documentStorage: document, snapshotStorage: snapshots)
        try store.save([SyntheticStoredProfile(name: "Original")], credentials: credentials)
        return (store, document, snapshots)
    }
}

private struct SyntheticStoredProfile: Codable {
    let name: String
    let secret: String?

    init(name: String, secret: String? = nil) { self.name = name; self.secret = secret }

    private enum CodingKeys: String, CodingKey { case name, secret }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
    }
}

private final class MemoryProfileDocumentStorage: ProfileDocumentStorage {
    var data: Data?
    var rejectWrites = false
    var failDurableCommit = false
    var writeCount = 0
    func readDocument() -> Data? { data }
    func writeDocument(_ data: Data) throws {
        writeCount += 1
        if !rejectWrites { self.data = data }
        if failDurableCommit { throw SecureProfilePersistenceError.documentWriteFailed }
    }
}

private final class MemoryProfileSnapshotStorage: ProfileSnapshotStorage {
    var values: [UUID: Data] = [:]
    var rejectWrites = false
    var rejectReads = false
    var corruptNewReadback = false
    var corruptedIDs: Set<UUID> = []
    var writeCount = 0

    func writeSnapshot(_ data: Data, id: UUID) -> Bool {
        writeCount += 1
        guard !rejectWrites else { return false }
        values[id] = data
        if corruptNewReadback { corruptedIDs.insert(id) }
        return true
    }

    func readSnapshot(id: UUID) throws -> Data? {
        if rejectReads { throw SecureProfilePersistenceError.secureReadFailed }
        if corruptedIDs.contains(id) { return Data("mismatched-synthetic-data".utf8) }
        return values[id]
    }

    func deleteSnapshot(id: UUID) -> Bool {
        values.removeValue(forKey: id)
        return true
    }
}
