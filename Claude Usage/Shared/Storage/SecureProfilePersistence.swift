import Foundation

protocol ProfileDocumentStorage: AnyObject {
    func readDocument() -> Data?
    /// Return only after the new document is committed durably, or throw.
    func writeDocument(_ data: Data) throws
}

protocol ProfileSnapshotStorage: AnyObject {
    func writeSnapshot(_ data: Data, id: UUID) -> Bool
    func readSnapshot(id: UUID) throws -> Data?
    @discardableResult func deleteSnapshot(id: UUID) -> Bool
}

enum SecureProfilePersistenceError: Error, LocalizedError, Equatable {
    case secureWriteFailed
    case secureReadFailed
    case documentWriteFailed
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .secureWriteFailed: return "The credentials could not be saved securely. Your previous saved profiles remain available."
        case .secureReadFailed: return "The saved credentials could not be read securely. Your saved profiles have not been replaced."
        case .documentWriteFailed: return "The profile changes could not be verified. Previous and staged credentials remain recoverable."
        case .invalidDocument: return "The saved profiles could not be read. The existing data has been preserved."
        }
    }
}

final class SecureProfilePersistence<Profiles: Codable> {
    struct LoadedProfiles {
        let profiles: Profiles
        let credentials: Data?
        let isLegacy: Bool
    }

    private struct Document: Codable {
        let formatVersion: Int
        let profiles: Profiles
        let credentialSnapshotID: UUID
    }

    private let documentStorage: ProfileDocumentStorage
    private let snapshotStorage: ProfileSnapshotStorage
    private var currentSnapshot: (id: UUID, data: Data)?
    private let lock = NSRecursiveLock()

    init(documentStorage: ProfileDocumentStorage, snapshotStorage: ProfileSnapshotStorage) {
        self.documentStorage = documentStorage
        self.snapshotStorage = snapshotStorage
    }

    // No custom cleanup needs an actor hop. Explicitly opt out only the
    // destructor: Swift 6.2 crashes optimizing inferred isolated destructors
    // of generic classes with reference storage (swiftlang/swift#85308).
    nonisolated deinit {}

    func load() throws -> LoadedProfiles? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = documentStorage.readDocument() else {
            currentSnapshot = nil
            return nil
        }
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(Document.self, from: data) {
            guard document.formatVersion == 1 else { throw SecureProfilePersistenceError.invalidDocument }
            let credentials: Data
            do {
                // A cached value cannot prove that a referenced Keychain item
                // still exists and is readable when committing another change.
                guard let stored = try snapshotStorage.readSnapshot(id: document.credentialSnapshotID) else {
                    throw SecureProfilePersistenceError.secureReadFailed
                }
                credentials = stored
            } catch {
                throw SecureProfilePersistenceError.secureReadFailed
            }
            currentSnapshot = (document.credentialSnapshotID, credentials)
            return LoadedProfiles(profiles: document.profiles, credentials: credentials, isLegacy: false)
        }
        guard let profiles = try? decoder.decode(Profiles.self, from: data) else {
            throw SecureProfilePersistenceError.invalidDocument
        }
        currentSnapshot = nil
        return LoadedProfiles(profiles: profiles, credentials: nil, isLegacy: true)
    }

    func save(_ profiles: Profiles, credentials: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        // Always establish the current reference first. An unreadable saved
        // snapshot must never turn into an empty/default credential overwrite.
        _ = try load()
        let previousSnapshot = currentSnapshot
        let stagedID: UUID
        if let previousSnapshot, previousSnapshot.data == credentials {
            stagedID = previousSnapshot.id
        } else {
            stagedID = UUID()
            guard snapshotStorage.writeSnapshot(credentials, id: stagedID) else {
                _ = snapshotStorage.deleteSnapshot(id: stagedID)
                throw SecureProfilePersistenceError.secureWriteFailed
            }
            do {
                guard try snapshotStorage.readSnapshot(id: stagedID) == credentials else {
                    throw SecureProfilePersistenceError.secureWriteFailed
                }
            } catch {
                _ = snapshotStorage.deleteSnapshot(id: stagedID)
                throw SecureProfilePersistenceError.secureWriteFailed
            }
        }

        let document = Document(formatVersion: 1, profiles: profiles, credentialSnapshotID: stagedID)
        let data = try JSONEncoder().encode(document)
        do {
            try documentStorage.writeDocument(data)
        } catch {
            // Either document may have reached disk. Retain both immutable
            // snapshots so a failed durable commit never destroys recovery.
            throw SecureProfilePersistenceError.documentWriteFailed
        }
        guard documentStorage.readDocument() == data else {
            // The write outcome is uncertain. Preserve both snapshots because
            // either reference may have reached durable storage.
            throw SecureProfilePersistenceError.documentWriteFailed
        }
        currentSnapshot = (stagedID, credentials)
        if let previousSnapshot, previousSnapshot.id != stagedID {
            _ = snapshotStorage.deleteSnapshot(id: previousSnapshot.id)
        }
    }
}
