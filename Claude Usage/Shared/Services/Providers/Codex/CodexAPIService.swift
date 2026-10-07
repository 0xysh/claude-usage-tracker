//
//  CodexAPIService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//
//  Fetches Codex usage from the ChatGPT backend
//  (GET {base}/wham/usage) and maps it onto the app's usage model.
//  Endpoint/headers verified against the MIT-licensed CodexBar project.
//

import Foundation

final class CodexAPIService {
    static let shared = CodexAPIService()

    private init() {}

    // MARK: - URL resolution

    /// Honor only official HTTPS ChatGPT origins. Never attach OAuth tokens to
    /// a locally configured proxy or silently fall back from an invalid setting.
    func usageURL(env: [String: String] = ProcessInfo.processInfo.environment,
                  configContents: String? = nil) throws -> URL {
        do {
            return try UsagePollingRequest.codexURL(baseURL: resolveBaseURL(env: env, configContents: configContents))
        } catch {
            throw AppError(code: .urlMalformed,
                           message: "Codex monitoring requires an official HTTPS ChatGPT endpoint.",
                           technicalDetails: "Configured usage destination was rejected before authentication.",
                           isRecoverable: true,
                           recoverySuggestion: "Remove the custom chatgpt_base_url override before connecting this monitor.")
        }
    }

    private func resolveBaseURL(env: [String: String], configContents: String?) -> String {
        // Non-nil configContents is authoritative (used by tests) — never
        // fall through to the real config.toml on disk.
        if let configContents {
            return Self.parseChatGPTBaseURL(from: configContents) ?? Constants.APIEndpoints.codexBase
        }
        let configURL = CodexAuthService.shared.codexHomeURL(env: env).appendingPathComponent("config.toml")
        if let contents = try? String(contentsOf: configURL, encoding: .utf8),
           let parsed = Self.parseChatGPTBaseURL(from: contents) {
            return parsed
        }
        return Constants.APIEndpoints.codexBase
    }

    /// Minimal TOML line scan for `chatgpt_base_url = "..."` (comments and
    /// quotes handled; a full TOML parser is overkill for one key).
    static func parseChatGPTBaseURL(from contents: String) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            // omittingEmptySubsequences must stay FALSE: a fully commented-out
            // line ("# chatgpt_base_url = ...") splits to ["", " chatgpt..."],
            // and dropping the leading empty piece would resurrect the comment
            // as the active setting.
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == "chatgpt_base_url" else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Fetch

    func fetchUsage(credentials: CodexCredentials) async throws -> CodexUsageResponse {
        let url = try usageURL()
        let request = try UsagePollingRequest.codex(baseURL: url.deletingLastPathComponent().deletingLastPathComponent().absoluteString,
                                                   accessToken: credentials.accessToken,
                                                   accountID: credentials.resolvedAccountId)

        let startTime = Date()
        let (data, response) = try await UsagePollingSessionDelegate.session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode

        NetworkLoggerService.shared.logRequest(
            url: url.absoluteString,
            method: "GET",
            requestBody: nil,
            responseData: data,
            statusCode: statusCode,
            duration: Date().timeIntervalSince(startTime),
            error: nil
        )

        switch statusCode {
        case .some(200...299):
            do {
                return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            } catch {
                throw AppError(
                    code: .apiParsingFailed,
                    message: "error.codex_invalid_response".localized,
                    technicalDetails: "Failed to decode wham/usage response: \(error.localizedDescription)",
                    isRecoverable: true
                )
            }
        case .some(401), .some(403):
            throw AppError(
                code: .providerAuthExpired,
                message: "error.codex_auth_expired".localized,
                technicalDetails: "wham/usage returned \(statusCode ?? 0)",
                isRecoverable: true,
                recoverySuggestion: "error.codex_auth_expired.suggestion".localized
            )
        default:
            throw AppError(
                code: .apiServerError,
                message: "error.codex_server_error".localized,
                technicalDetails: "wham/usage returned \(statusCode.map(String.init) ?? "no status"): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")",
                isRecoverable: true
            )
        }
    }

    // MARK: - Mapping

    /// Maps the Codex response onto the app's usage model. Windows are
    /// classified by duration (not position): the ~5h window → session
    /// fields, the ~7d window → weekly fields. Codex reports percentages
    /// only, so token/limit fields stay 0 (the UI hides token-based rows).
    ///
    /// `previous` (the profile's cached usage) anchors the reset-time
    /// fallbacks: when the API omits `reset_at`, a now-relative fallback
    /// would change every fetch, and MenuBarManager's reset detection treats
    /// any minute-level change of the reset time as a reset — spamming usage
    /// history with bogus reset snapshots. Reusing the previous (still
    /// future) reset time keeps the value stable across refreshes.
    static func mapToUsage(_ response: CodexUsageResponse, previous: ClaudeUsage? = nil) -> ClaudeUsage {
        let (session, weekly) = CodexRateWindowNormalizer.normalize(
            primary: response.rateLimit?.primaryWindow,
            secondary: response.rateLimit?.secondaryWindow
        )

        var usage = ClaudeUsage.empty
        usage.weeklyLimit = 0  // .empty uses a placeholder token limit; Codex has none

        usage.sessionPercentage = session?.usedPercent ?? 0
        usage.sessionUsageAvailable = session != nil
        if let sessionReset = session?.resetDate {
            usage.sessionResetTime = sessionReset
        } else if let previousReset = previous?.sessionResetTime, previousReset > Date() {
            usage.sessionResetTime = previousReset
        } else {
            usage.sessionResetTime = Date().addingTimeInterval(TimeInterval(session?.limitWindowSeconds ?? 5 * 60 * 60))
        }

        usage.weeklyPercentage = weekly?.usedPercent ?? 0
        usage.weeklyUsageAvailable = weekly != nil
        if let weeklyReset = weekly?.resetDate {
            usage.weeklyResetTime = weeklyReset
        } else if let previousReset = previous?.weeklyResetTime, previousReset > Date() {
            usage.weeklyResetTime = previousReset
        } else if let seconds = weekly?.limitWindowSeconds {
            usage.weeklyResetTime = Date().addingTimeInterval(TimeInterval(seconds))
        } else {
            usage.weeklyResetTime = Date().addingTimeInterval(7 * 24 * 60 * 60)
        }

        usage.planType = response.planType
        if let credits = response.credits {
            usage.creditsUnlimited = credits.unlimited
            usage.creditsBalance = credits.balance
        }

        usage.lastUpdated = Date()
        usage.userTimezone = .current
        return usage
    }
}
