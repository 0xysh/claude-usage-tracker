//
//  CodexUsageProvider.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//

import Foundation

final class CodexUsageProvider: UsageProviderService {
    static let shared = CodexUsageProvider()

    let provider: Provider = .codex

    private let authService: CodexAuthService
    private let requestUsage: (CodexCredentials) async throws -> CodexUsageResponse
    private let profileContext: @MainActor () -> (activeID: UUID?, profiles: [Profile])
    private let saveProfile: @MainActor (Profile) -> Bool

    init(authService: CodexAuthService = .shared,
         requestUsage: @escaping (CodexCredentials) async throws -> CodexUsageResponse = {
             try await CodexAPIService.shared.fetchUsage(credentials: $0)
         },
         profileContext: @escaping @MainActor () -> (activeID: UUID?, profiles: [Profile]) = {
             (ProfileManager.shared.activeProfile?.id, ProfileManager.shared.profiles)
         },
         saveProfile: @escaping @MainActor (Profile) -> Bool = {
             ProfileManager.shared.updateProfile($0)
             return ProfileStore.shared.lastPersistenceError == nil
         }) {
        self.authService = authService
        self.requestUsage = requestUsage
        self.profileContext = profileContext
        self.saveProfile = saveProfile
    }

    func hasCredentials(for profile: Profile) -> Bool {
        profile.hasUsageCredentials
    }

    /// File-based credentials are reloaded from Codex's current login; only
    /// manually managed profiles rotate their tokens here. On a 401/403,
    /// reload or refresh once and retry, then surface the login error.
    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage {
        var credentials = try authService.loadCredentials(for: profile)
        credentials = try await authService.refreshIfNeeded(credentials, for: profile)
        var accountID = try authorizedFileAccount(credentials, for: profile)

        let previousUsage = profile.claudeUsage
        let response: CodexUsageResponse
        do {
            response = try await requestUsage(credentials)
        } catch let error as AppError where error.code == .providerAuthExpired {
            guard !credentials.refreshToken.isEmpty else { throw error }
            let refreshed = try await authService.refreshIfNeeded(credentials, for: profile, force: true)
            // Codex may have changed accounts while handling its own login.
            // Recheck the reloaded identity before attaching it to a retry.
            accountID = try authorizedFileAccount(refreshed, for: profile)
            response = try await requestUsage(refreshed)
        }
        let windows = CodexRateWindowNormalizer.normalize(primary: response.rateLimit?.primaryWindow,
                                                          secondary: response.rateLimit?.secondaryWindow)
        guard windows.session != nil || windows.weekly != nil else {
            throw AppError(code: .apiParsingFailed,
                           message: "Codex did not return a usable usage window.",
                           isRecoverable: true,
                           recoverySuggestion: "Refresh again. Your last known usage has been preserved.")
        }
        if let accountID { try recordSuccessfulFileConnection(accountID, for: profile) }
        return CodexAPIService.mapToUsage(response, previous: previousUsage)
    }

    /// The shared file represents one account. Existing bindings can be used
    /// in a combined/background view; only an active, unbound profile can claim
    /// that identity, and only after its usage request succeeds.
    private func authorizedFileAccount(_ credentials: CodexCredentials, for profile: Profile) throws -> String? {
        guard profile.codexCredentialsJSON == nil else { return nil }
        guard let accountID = credentials.resolvedAccountId,
              !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw connectionError("Codex's current credentials do not identify a ChatGPT account.",
                                  suggestion: "Sign in with your ChatGPT account in Codex, then select this profile and test its connection.")
        }
        let context = profileContext()
        guard let current = context.profiles.first(where: { $0.id == profile.id }),
              current.provider == .codex, current.codexCredentialsJSON == nil else {
            throw changedProfileError()
        }
        if let boundID = current.codexAccountID {
            guard boundID == accountID else {
                throw connectionError("The signed-in Codex account does not match this profile.",
                                      suggestion: "Connect the intended account in Codex before trying again.")
            }
        } else if context.activeID != profile.id {
            throw connectionError("This Codex profile needs its first connection check.",
                                  suggestion: "Select this Codex profile and test its connection once before showing it together with other profiles.")
        }
        return accountID
    }

    private func recordSuccessfulFileConnection(_ accountID: String, for profile: Profile) throws {
        let context = profileContext()
        guard var current = context.profiles.first(where: { $0.id == profile.id }),
              current.provider == .codex, current.codexCredentialsJSON == nil else {
            throw changedProfileError()
        }
        if let boundID = current.codexAccountID {
            guard boundID == accountID else { throw changedProfileError() }
            return
        }
        guard context.activeID == profile.id else { throw changedProfileError() }
        current.codexAccountID = accountID
        guard saveProfile(current) else {
            throw AppError(code: .storageWriteFailed,
                           message: "The Codex account connection could not be saved securely.",
                           isRecoverable: true,
                           recoverySuggestion: "Select this profile and test its connection again after resolving the storage error.")
        }
    }

    private func changedProfileError() -> AppError {
        connectionError("The Codex profile changed while its connection was being checked.",
                        suggestion: "Select the intended profile and test its connection again.")
    }

    private func connectionError(_ message: String, suggestion: String) -> AppError {
        AppError(code: .providerCredentialsNotFound, message: message,
                 isRecoverable: true, recoverySuggestion: suggestion)
    }
}
