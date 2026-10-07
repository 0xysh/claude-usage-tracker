// In-memory dependencies for tests of the exact ProfileManager/Profile sources.
// No Keychain, defaults, account files, network, statusline, or terminal writes.
import Foundation

enum Provider: String, Codable, Equatable {
    case anthropic, codex
    var descriptor: Descriptor { Descriptor(capabilities: Capabilities(cliAccountSync: self == .anthropic)) }
    struct Descriptor { let capabilities: Capabilities }
    struct Capabilities { let cliAccountSync: Bool; var tokenCounts: Bool { true } }
}
struct ClaudeUsage: Codable, Equatable { var sessionPercentage = 0 }
struct APIUsage: Codable, Equatable {}
struct MenuBarIconConfiguration: Codable, Equatable {
    static let `default` = Self()
    var metrics: [Metric] = []
    struct Metric: Codable, Equatable { var weekDisplayMode: Mode }
    enum Mode: String, Codable { case tokens, percentage }
}
struct NotificationSettings: Codable, Equatable {}
struct MultiProfileDisplayConfig {
    static let `default` = Self()
    var iconStyle: Style = .separate
    var showWeek = true
    enum Style: String { case separate }
}
enum ProfileDisplayMode: String { case single, multi }
enum SecureProfilePersistenceError: Error, Equatable {
    case secureWriteFailed, secureReadFailed, invalidDocument
    var errorDescription: String? { "Synthetic persistence failure" }
}
enum ErrorCode { case storageReadFailed, storageWriteFailed }
struct AppError: Error {
    init(code: ErrorCode, message: String, recoverySuggestion: String) {}
}
extension Notification.Name { static let credentialsChanged = Self("synthetic.credentialsChanged") }

@MainActor final class ProfileStore {
    static let shared = ProfileStore()
    static let persistenceStatusChanged = Notification.Name("synthetic.persistenceChanged")
    var stored: [Profile] = []
    var activeID: UUID?
    var saved: [[Profile]] = []
    var lastPersistenceError: SecureProfilePersistenceError?
    func loadProfiles() -> [Profile] { stored }
    func saveProfiles(_ profiles: [Profile]) -> Bool {
        stored = profiles
        saved.append(profiles)
        return true
    }
    func loadActiveProfileId() -> UUID? { activeID }
    func saveActiveProfileId(_ id: UUID) { activeID = id }
    func loadDisplayMode() -> ProfileDisplayMode { .single }
    func saveDisplayMode(_ mode: ProfileDisplayMode) {}
    func loadMultiProfileConfig() -> MultiProfileDisplayConfig { .default }
    func saveMultiProfileConfig(_ config: MultiProfileDisplayConfig) {}
    func deleteProfileSecrets(_ id: UUID) { preconditionFailure("Unrelated destructive operation") }
    func loadProfileCredentials(_ id: UUID) throws -> ProfileCredentials {
        preconditionFailure("Credential reads outside activation are forbidden")
    }
}

@MainActor final class ClaudeCodeSyncService {
    static let shared = ClaudeCodeSyncService()
    var refresh: ((UUID) async -> String?)?
    var refreshed: [UUID] = []
    var applied: [Profile] = []
    var resynced: [UUID] = []
    var resync: ((UUID) -> Void)?
    func ensureFreshCredentials(for id: UUID, allowRotation: Bool) async -> String? {
        precondition(allowRotation, "Activation explicitly hands refreshed credentials to the CLI")
        refreshed.append(id)
        return await refresh?(id)
    }
    func applyProfileCredentials(_ id: UUID) throws {
        guard let profile = ProfileStore.shared.stored.first(where: { $0.id == id }) else {
            throw ProfileError.profileNotFound
        }
        applied.append(profile)
    }
    func resyncBeforeSwitching(for id: UUID) throws { resynced.append(id); resync?(id) }
    func readSystemCredentials() throws -> String? { preconditionFailure("Real credential reads are forbidden") }
    func isTokenExpired(_ json: String) -> Bool { false }
    func extractAccessToken(from json: String) -> String? { preconditionFailure("Real token reads are forbidden") }
    func syncToProfile(_ id: UUID) throws { preconditionFailure("Unrelated account sync") }
}

@MainActor final class CodexAuthService {
    static let shared = CodexAuthService()
    func authFileExists() -> Bool { preconditionFailure("Codex files are forbidden") }
}
@MainActor final class StatuslineService {
    static let shared = StatuslineService()
    var names: [String] = []
    func updateScriptsIfInstalled() throws {}
    func updateProfileNameInConfig(_ name: String) throws { names.append(name) }
}
@MainActor final class ErrorPresenter {
    static let shared = ErrorPresenter()
    func showAlert(for error: AppError) { preconditionFailure("Unexpected persistence failure") }
}
@MainActor final class LoggingService {
    static let shared = LoggingService()
    func log(_ message: String) {}
    func logError(_ message: String, error: Error? = nil) {}
}
@MainActor final class TerminalLauncherService {
    static let shared = TerminalLauncherService()
    func uninstall(_ profile: Profile) { preconditionFailure("Unrelated destructive operation") }
}
@MainActor final class UsageHistoryService {
    static let shared = UsageHistoryService()
    func deleteHistory(for id: UUID) { preconditionFailure("Unrelated destructive operation") }
}
enum FunnyNameGenerator {
    static func getRandomName(excluding names: [String]) -> String { "Synthetic" }
}
