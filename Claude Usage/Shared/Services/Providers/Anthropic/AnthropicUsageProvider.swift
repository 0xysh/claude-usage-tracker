//
//  AnthropicUsageProvider.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//
//  Both active and per-profile refreshes use the same profile-aware source
//  selection while keeping the existing API requests and refresh policy.
//

import Foundation

final class AnthropicUsageProvider: UsageProviderService {
    static let shared = AnthropicUsageProvider()

    let provider: Provider = .anthropic

    // Concrete type: the per-profile fetch overloads (sessionKey/oauthAccessToken)
    // are not part of APIServiceProtocol.
    private let apiService: ClaudeAPIService
    private let cliSource: AnthropicCLICredentialSource
    private let activeProfileID: @MainActor () -> UUID?
    private let credentialDiagnostics: @MainActor (String) -> Void

    init(apiService: ClaudeAPIService = ClaudeAPIService(),
         cliSource: AnthropicCLICredentialSource = ClaudeCodeSyncService.shared,
         activeProfileID: @escaping @MainActor () -> UUID? = { ProfileManager.shared.activeProfile?.id },
         credentialDiagnostics: @escaping @MainActor (String) -> Void = { LoggingService.shared.log($0) }) {
        self.apiService = apiService
        self.cliSource = cliSource
        self.activeProfileID = activeProfileID
        self.credentialDiagnostics = credentialDiagnostics
    }

    /// Known CLI configuration also allows a refresh attempt when expired or
    /// incomplete, so the UI receives a useful error instead of silently skipping.
    func hasCredentials(for profile: Profile) -> Bool {
        profile.claudeSessionKey != nil || hasCLIConfiguration(profile)
            || (profile.id == activeProfileID() && cliSource.hasUsableSystemCredentials())
    }

    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage {
        // Browser sign-in can precede organization discovery. Preserve that flow
        // before evaluating the CLI credentials, using the existing API methods.
        if let sessionKey = profile.claudeSessionKey {
            let orgId: String
            if let savedOrgId = profile.organizationId {
                orgId = savedOrgId
            } else {
                // The active-profile helper caches and persists a global org ID.
                // Discover with this profile's explicit key without touching it.
                let organizations = try await apiService.fetchAllOrganizations(sessionKey: sessionKey)
                guard let organization = organizations.first else {
                    throw AppError(code: .apiParsingFailed, message: "No organizations found for this Claude account.",
                                   recoverySuggestion: "Choose a Claude account with access to an organization, then refresh.")
                }
                orgId = organization.uuid
            }
            return try await apiService.fetchUsageData(sessionKey: sessionKey, organizationId: orgId)
        }

        let savedCLI = profile.cliCredentialsJSON != nil
        let pinned = profile.customKeychainServiceName != nil
        let active = profile.id == activeProfileID()
        var selectedJSON: String?
        var selectedToken: String?
        var selectedExpired = false
        var expiredTokenSeen = false

        func select(_ json: String) {
            selectedJSON = json
            selectedToken = cliSource.extractAccessToken(from: json).flatMap {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
            }
            selectedExpired = cliSource.isTokenExpired(json)
            expiredTokenSeen = expiredTokenSeen || (selectedToken != nil && selectedExpired)
        }

        // Use the existing source-aware selector and its existing rotation
        // policy; ordinary polling never requests an activation-only rotation.
        if savedCLI || pinned {
            if let json = await cliSource.ensureFreshCredentials(for: profile.id, allowRotation: false)
                ?? profile.cliCredentialsJSON {
                select(json)
                if let token = selectedToken, !selectedExpired {
                    return try await apiService.fetchUsageData(oauthAccessToken: token)
                }
            }
        }

        // A generic CLI session is only a fallback for the active profile. For a
        // bound account require a positive identity or nonempty lineage match;
        // two missing identities/tokens never count as the same account.
        if active, let systemJSON = try? cliSource.readSystemCredentials(),
           systemAccountMatches(profile, credentials: systemJSON) {
            select(systemJSON)
            if let token = selectedToken, !selectedExpired {
                return try await apiService.fetchUsageData(oauthAccessToken: token)
            }
        }

        credentialDiagnostics("AnthropicUsageProvider: credential selection failed savedCLI=\(savedCLI) usableJSONPresent=\(selectedJSON != nil) tokenPresent=\(selectedToken != nil) expired=\(selectedExpired) pinned=\(pinned) active=\(active)")

        // Do not return a persisted snapshot as a successful live refresh. It
        // remains on Profile for the popup's last-known-data and error state.
        if expiredTokenSeen {
            throw AppError(code: .sessionKeyExpired, message: "Claude CLI credentials have expired.",
                           recoverySuggestion: "Sign in through Claude Code again, sync this account, then refresh.")
        }
        if hasCLIConfiguration(profile) || selectedJSON != nil {
            throw AppError(code: .sessionKeyInvalid, message: "Claude CLI credentials are missing a valid access token.",
                           recoverySuggestion: "Sign in through Claude Code, sync this account, then refresh.")
        }
        throw AppError(code: .sessionKeyNotFound, message: "No usable Claude credentials are available.",
                       recoverySuggestion: "Connect a Claude account or sync your CLI account, then refresh.")
    }

    func fetchUsageForActiveProfile(_ profile: Profile) async throws -> ClaudeUsage {
        try await fetchUsage(for: profile)
    }

    private func hasCLIConfiguration(_ profile: Profile) -> Bool {
        profile.cliCredentialsJSON != nil || profile.customKeychainServiceName != nil
            || profile.hasCliAccount || profile.oauthAccountJSON != nil
    }

    private func systemAccountMatches(_ profile: Profile, credentials: String) -> Bool {
        guard hasCLIConfiguration(profile) else { return true }
        let profileIdentity = cliSource.accountIdentity(fromOAuthAccountJSON: profile.oauthAccountJSON)
        let systemIdentity = cliSource.accountIdentity(fromOAuthAccountJSON: cliSource.readOAuthAccount())
        if let profileIdentity, let systemIdentity { return profileIdentity == systemIdentity }
        guard let savedJSON = profile.cliCredentialsJSON,
              let savedLineage = cliSource.extractRefreshToken(from: savedJSON), !savedLineage.isEmpty,
              let systemLineage = cliSource.extractRefreshToken(from: credentials), !systemLineage.isEmpty else { return false }
        return savedLineage == systemLineage
    }

}

/// Narrow injection seam for selection tests; the production implementation
/// remains the existing Claude Code credential service and refresh policy.
protocol AnthropicCLICredentialSource {
    func ensureFreshCredentials(for profileId: UUID, allowRotation: Bool) async -> String?
    func readSystemCredentials() throws -> String?
    func readOAuthAccount() -> String?
    func accountIdentity(fromOAuthAccountJSON json: String?) -> String?
    func extractAccessToken(from jsonData: String) -> String?
    func extractRefreshToken(from jsonData: String) -> String?
    func isTokenExpired(_ jsonData: String) -> Bool
    func hasUsableSystemCredentials() -> Bool
}

extension ClaudeCodeSyncService: AnthropicCLICredentialSource {}
