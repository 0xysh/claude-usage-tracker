#if SECURE_PROFILE_ISOLATED_TESTS
import Foundation

// Only for the unhosted persistence harness. Profile.swift, ProfileStore.swift
// and SecureProfilePersistence.swift are the exact production sources. The
// unrelated UI/provider types below are inert; any accidental credential-store
// or provider operation traps instead of touching a real login or auth file.
enum Provider: String, Codable, Equatable { case anthropic, codex }
struct ClaudeUsage: Codable, Equatable {}
struct APIUsage: Codable, Equatable {}
struct MenuBarIconConfiguration: Codable, Equatable {
    static let `default` = MenuBarIconConfiguration()
}
struct NotificationSettings: Codable, Equatable {}
struct MultiProfileDisplayConfig: Codable, Equatable {
    static let `default` = MultiProfileDisplayConfig()
}

final class LoggingService {
    static let shared = LoggingService()
    func log(_ message: String) {}
    func logError(_ message: String, error: Error? = nil) {}
    func logStorageError(_ operation: String, error: Error) {}
}

final class KeychainService: ProfileSnapshotStorage, ProfileLegacySecretStorage {
    static let shared = KeychainService()
    enum ProfileSecretField { case claudeSessionKey, apiSessionKey, cliCredentialsJSON, codexCredentialsJSON }
    func writeSnapshot(_ data: Data, id: UUID) -> Bool { preconditionFailure("Tests must inject synthetic snapshot storage") }
    func readSnapshot(id: UUID) throws -> Data? { preconditionFailure("Tests must inject synthetic snapshot storage") }
    func deleteSnapshot(id: UUID) -> Bool { preconditionFailure("Tests must inject synthetic snapshot storage") }
    func readProfileSecret(profileId: UUID, field: ProfileSecretField) throws -> String? { preconditionFailure("Tests must inject synthetic legacy storage") }
    func deleteAllProfileSecrets(profileId: UUID) { preconditionFailure("Tests must inject synthetic legacy storage") }
}

final class CodexAuthService {
    static let shared = CodexAuthService()
    func authFileExists() -> Bool { preconditionFailure("Auth file access is forbidden in persistence tests") }
}

final class ClaudeCodeSyncService {
    static let shared = ClaudeCodeSyncService()
    func isTokenExpired(_ json: String) -> Bool { preconditionFailure("CLI account access is forbidden in persistence tests") }
}
#endif
