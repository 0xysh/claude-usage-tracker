//
//  ProfileStore.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation

/// Manages storage and retrieval of profiles and profile-related data
class ProfileStore {
    static let shared = ProfileStore()

    static let persistenceStatusChanged = Notification.Name("ProfileStore.persistenceStatusChanged")

    private let defaults: UserDefaults
    private let legacySecrets: ProfileLegacySecretStorage
    private let persistence: SecureProfilePersistence<[Profile]>
    private let lock = NSRecursiveLock()
    private var pendingProfiles: [Profile]?
    private var persistenceError: SecureProfilePersistenceError?

    var lastPersistenceError: SecureProfilePersistenceError? {
        lock.lock()
        defer { lock.unlock() }
        return persistenceError
    }

    private enum Keys {
        static let profiles = "profiles_v3"
        static let activeProfileId = "activeProfileId"
        static let displayMode = "profileDisplayMode"
        static let multiProfileConfig = "multiProfileDisplayConfig"
    }

    init(defaults: UserDefaults = .standard,
         documentStorage: ProfileDocumentStorage? = nil,
         snapshotStorage: ProfileSnapshotStorage = KeychainService.shared,
         legacySecrets: ProfileLegacySecretStorage = KeychainService.shared) {
        self.defaults = defaults
        self.legacySecrets = legacySecrets
        self.persistence = SecureProfilePersistence(
            documentStorage: documentStorage ?? DefaultsProfileDocumentStorage(defaults: defaults, key: Keys.profiles),
            snapshotStorage: snapshotStorage
        )
    }

    // MARK: - Profile Management

    /// Stage a complete immutable secure snapshot before committing metadata.
    /// Failure preserves attempted edits in memory and leaves durable originals
    /// available; credentials are never newly written to UserDefaults.
    @discardableResult
    func saveProfiles(_ profiles: [Profile]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pendingProfiles = profiles
        do {
            let previous = try persistence.load()
            if let previous, previous.isLegacy {
                // A denied legacy read is not an absent credential. Do not
                // replace a legacy document until all of it is recoverable.
                _ = try hydrateLegacyProfiles(previous.profiles)
            } else if let previous {
                guard let data = previous.credentials,
                      let snapshot = try? JSONDecoder().decode(ProfileCredentialSnapshot.self, from: data) else {
                    throw SecureProfilePersistenceError.secureReadFailed
                }
                _ = try snapshot.hydrate(previous.profiles)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let credentials = try encoder.encode(ProfileCredentialSnapshot(profiles: profiles))
            try persistence.save(profiles, credentials: credentials)
            pendingProfiles = nil
            setPersistenceError(nil)
            if let previous, previous.isLegacy {
                // The new snapshot and metadata are durably committed. Legacy
                // canonical keys can now be removed, including deleted profiles.
                for profile in previous.profiles {
                    legacySecrets.deleteAllProfileSecrets(profileId: profile.id)
                }
            }
            return true
        } catch {
            setPersistenceError(error as? SecureProfilePersistenceError ?? .invalidDocument)
            return false
        }
    }

    func loadProfiles() -> [Profile] {
        lock.lock()
        defer { lock.unlock() }
        if let pendingProfiles { return pendingProfiles }
        do {
            guard let loaded = try persistence.load() else {
                setPersistenceError(nil)
                return []
            }
            if loaded.isLegacy {
                let profiles = try hydrateLegacyProfiles(loaded.profiles)
                // On failure the old bytes and canonical Keychain items remain
                // intact, and the hydrated edit remains available in memory.
                _ = saveProfiles(profiles)
                return profiles
            }
            guard let credentials = loaded.credentials,
                  let snapshot = try? JSONDecoder().decode(ProfileCredentialSnapshot.self, from: credentials) else {
                throw SecureProfilePersistenceError.secureReadFailed
            }
            let profiles = try snapshot.hydrate(loaded.profiles)
            setPersistenceError(nil)
            return profiles
        } catch {
            setPersistenceError(error as? SecureProfilePersistenceError ?? .invalidDocument)
            return []
        }
    }

    private func hydrateLegacyProfiles(_ profiles: [Profile]) throws -> [Profile] {
        var hydrated = profiles
        do {
            for index in hydrated.indices {
                let id = hydrated[index].id
                if hydrated[index].claudeSessionKey == nil {
                    hydrated[index].claudeSessionKey = try legacySecrets.readProfileSecret(profileId: id, field: .claudeSessionKey)
                }
                if hydrated[index].apiSessionKey == nil {
                    hydrated[index].apiSessionKey = try legacySecrets.readProfileSecret(profileId: id, field: .apiSessionKey)
                }
                if hydrated[index].cliCredentialsJSON == nil {
                    hydrated[index].cliCredentialsJSON = try legacySecrets.readProfileSecret(profileId: id, field: .cliCredentialsJSON)
                }
                if hydrated[index].codexCredentialsJSON == nil {
                    hydrated[index].codexCredentialsJSON = try legacySecrets.readProfileSecret(profileId: id, field: .codexCredentialsJSON)
                }
            }
        } catch {
            throw SecureProfilePersistenceError.secureReadFailed
        }
        return hydrated
    }

    private func setPersistenceError(_ error: SecureProfilePersistenceError?) {
        let changed = persistenceError != error
        persistenceError = error
        if let error { LoggingService.shared.logError("ProfileStore: " + (error.errorDescription ?? "Profile storage failed")) }
        if changed {
            NotificationCenter.default.post(name: Self.persistenceStatusChanged, object: self,
                                            userInfo: error.map { ["error": $0] })
        }
    }

    /// Legacy cleanup is safe only after this profile has disappeared from a
    /// durably committed document. Pending deletion never destroys old secrets.
    func deleteProfileSecrets(_ profileId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard persistenceError == nil,
              let loaded = try? persistence.load(),
              !loaded.profiles.contains(where: { $0.id == profileId }) else { return }
        legacySecrets.deleteAllProfileSecrets(profileId: profileId)
    }

    func saveActiveProfileId(_ id: UUID) {
        defaults.set(id.uuidString, forKey: Keys.activeProfileId)
    }

    func loadActiveProfileId() -> UUID? {
        guard let uuidString = defaults.string(forKey: Keys.activeProfileId) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    func saveDisplayMode(_ mode: ProfileDisplayMode) {
        defaults.set(mode.rawValue, forKey: Keys.displayMode)
    }

    func loadDisplayMode() -> ProfileDisplayMode {
        guard let rawValue = defaults.string(forKey: Keys.displayMode),
              let mode = ProfileDisplayMode(rawValue: rawValue) else {
            return .single
        }
        return mode
    }

    // MARK: - Multi-Profile Display Config

    func saveMultiProfileConfig(_ config: MultiProfileDisplayConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: Keys.multiProfileConfig)
        } catch {
            LoggingService.shared.logStorageError("saveMultiProfileConfig", error: error)
        }
    }

    func loadMultiProfileConfig() -> MultiProfileDisplayConfig {
        guard let data = defaults.data(forKey: Keys.multiProfileConfig) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(MultiProfileDisplayConfig.self, from: data)
        } catch {
            LoggingService.shared.logStorageError("loadMultiProfileConfig", error: error)
            return .default
        }
    }

    // MARK: - Credential Helpers

    func saveProfileCredentials(_ profileId: UUID, credentials: ProfileCredentials) throws {
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw NSError(domain: "ProfileStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Profile not found"])
        }

        // Update credentials directly in profile
        profiles[index].claudeSessionKey = credentials.claudeSessionKey
        profiles[index].organizationId = credentials.organizationId
        profiles[index].apiSessionKey = credentials.apiSessionKey
        profiles[index].apiOrganizationId = credentials.apiOrganizationId
        profiles[index].cliCredentialsJSON = credentials.cliCredentialsJSON

        guard saveProfiles(profiles) else {
            throw lastPersistenceError ?? SecureProfilePersistenceError.secureWriteFailed
        }
    }

    func loadProfileCredentials(_ profileId: UUID) throws -> ProfileCredentials {
        let profiles = loadProfiles()
        if let error = lastPersistenceError, pendingProfiles == nil { throw error }
        guard let profile = profiles.first(where: { $0.id == profileId }) else {
            throw NSError(domain: "ProfileStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Profile not found"])
        }

        return ProfileCredentials(
            claudeSessionKey: profile.claudeSessionKey,
            organizationId: profile.organizationId,
            apiSessionKey: profile.apiSessionKey,
            apiOrganizationId: profile.apiOrganizationId,
            cliCredentialsJSON: profile.cliCredentialsJSON
        )
    }
}


protocol ProfileLegacySecretStorage: AnyObject {
    func readProfileSecret(profileId: UUID, field: KeychainService.ProfileSecretField) throws -> String?
    func deleteAllProfileSecrets(profileId: UUID)
}

private final class DefaultsProfileDocumentStorage: ProfileDocumentStorage {
    private let defaults: UserDefaults
    private let key: String
    init(defaults: UserDefaults, key: String) { self.defaults = defaults; self.key = key }
    func readDocument() -> Data? { defaults.data(forKey: key) }
    func writeDocument(_ data: Data) throws {
        defaults.set(data, forKey: key)
        // Ordinary settings need no explicit synchronization. Here cleanup of
        // the previous secure snapshot requires a disk-commit fence: Apple
        // documents true as successful disk persistence of pending updates.
        guard defaults.synchronize() else { throw SecureProfilePersistenceError.documentWriteFailed }
    }
}

private struct ProfileCredentialSnapshot: Codable {
    private struct Secrets: Codable {
        let claudeSessionKey: String?
        let apiSessionKey: String?
        let cliCredentialsJSON: String?
        let codexCredentialsJSON: String?
    }
    private let profiles: [String: Secrets]

    init(profiles: [Profile]) {
        self.profiles = profiles.reduce(into: [:]) { result, profile in
            result[profile.id.uuidString] = Secrets(claudeSessionKey: profile.claudeSessionKey,
                                                   apiSessionKey: profile.apiSessionKey,
                                                   cliCredentialsJSON: profile.cliCredentialsJSON,
                                                   codexCredentialsJSON: profile.codexCredentialsJSON)
        }
    }

    func hydrate(_ metadata: [Profile]) throws -> [Profile] {
        try metadata.map { profile in
            guard let secrets = profiles[profile.id.uuidString] else { throw SecureProfilePersistenceError.secureReadFailed }
            var hydrated = profile
            hydrated.claudeSessionKey = secrets.claudeSessionKey
            hydrated.apiSessionKey = secrets.apiSessionKey
            hydrated.cliCredentialsJSON = secrets.cliCredentialsJSON
            hydrated.codexCredentialsJSON = secrets.codexCredentialsJSON
            return hydrated
        }
    }
}
