#!/bin/bash
set -euo pipefail

# Exact Profile/Auth/Provider sources with synthetic context and transport.
# The unrelated app dependencies trap before any shared store/network access.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
test_support="$developer_dir/Platforms/MacOSX.platform/Developer"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/codex-account-binding.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
bundle="$test_directory/CodexAccountBindingTests.xctest"
mkdir -p "$bundle/Contents/MacOS"

cat > "$test_directory/AppDependencies.swift" <<'SWIFT'
import Foundation
enum Provider: String, Codable, Equatable { case anthropic, codex }
struct APIUsage: Codable, Equatable {}
struct MenuBarIconConfiguration: Codable, Equatable { static let `default` = Self() }
struct NotificationSettings: Codable, Equatable {}
enum ErrorCode { case providerCredentialsNotFound, providerAuthExpired, providerAuthRefreshFailed, storageEncodingFailed, storageWriteFailed, apiParsingFailed, urlMalformed, apiServerError }
struct AppError: Error {
    let code: ErrorCode
    init(code: ErrorCode, message: String, technicalDetails: String? = nil,
         isRecoverable: Bool, recoverySuggestion: String? = nil) { self.code = code }
}
extension String { var localized: String { self } }
enum Constants {
    enum APIEndpoints {
        static let codexTokenRefresh = "https://auth.example.invalid/oauth/token"
        static let codexBase = "https://chatgpt.com/backend-api"
    }
}
final class LoggingService {
    static let shared = LoggingService()
    func logError(_ message: String, error: Error? = nil) {}
}
final class NetworkLoggerService {
    static let shared = NetworkLoggerService()
    func logRequest(url: String, method: String, requestBody: Data?, responseData: Data?,
                    statusCode: Int?, duration: TimeInterval?, error: Error?) {}
}
final class ProfileManager {
    static let shared = ProfileManager()
    var profiles: [Profile] { preconditionFailure("Inject synthetic profile context") }
    var activeProfile: Profile? { preconditionFailure("Inject synthetic active profile") }
    func updateProfile(_ profile: Profile) { preconditionFailure("Inject synthetic profile persistence") }
}
final class ProfileStore {
    static let shared = ProfileStore()
    var lastPersistenceError: Error? { preconditionFailure("Inject synthetic profile persistence") }
}
final class ClaudeCodeSyncService {
    static let shared = ClaudeCodeSyncService()
    func isTokenExpired(_ json: String) -> Bool { preconditionFailure("Claude credentials are forbidden") }
}
final class SharedDataStore {
    static let shared = SharedDataStore()
    func uses24HourTime() -> Bool { false }
}
SWIFT

xcrun swiftc -emit-library -emit-module -enable-testing -module-name Claude_Usage \
    -swift-version 5 -default-isolation MainActor \
    -enable-upcoming-feature DisableOutwardActorInference \
    -enable-upcoming-feature InferSendableFromCaptures \
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
    -enable-upcoming-feature MemberImportVisibility \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -module-cache-path "$test_directory/module-cache" \
    -emit-module-path "$test_directory/Claude_Usage.swiftmodule" \
    "$test_directory/AppDependencies.swift" \
    "$repo_root/Claude Usage/Shared/Models/ClaudeUsage.swift" \
    "$repo_root/Claude Usage/Shared/Models/Profile.swift" \
    "$repo_root/Claude Usage/Shared/Extensions/Date+Extensions.swift" \
    "$repo_root/Claude Usage/Shared/Protocols/UsageProviderService.swift" \
    "$repo_root/Claude Usage/Shared/Utilities/UsagePollingRequest.swift" \
    "$repo_root/Claude Usage/Shared/Services/Providers/Codex/CodexAuthService.swift" \
    "$repo_root/Claude Usage/Shared/Services/Providers/Codex/CodexAPIService+Types.swift" \
    "$repo_root/Claude Usage/Shared/Services/Providers/Codex/CodexAPIService.swift" \
    "$repo_root/Claude Usage/Shared/Services/Providers/Codex/CodexUsageProvider.swift" \
    -o "$test_directory/libClaude_Usage.dylib"

xcrun swiftc -emit-library -module-name CodexAccountBindingTests -swift-version 5 \
    -module-cache-path "$test_directory/module-cache" \
    -I "$test_directory" -I "$test_support/usr/lib" \
    -F "$test_support/Library/Frameworks" \
    -L "$test_directory" -lClaude_Usage -L "$test_support/usr/lib" \
    -Xlinker -rpath -Xlinker "$test_directory" \
    -Xlinker -rpath -Xlinker "$test_support/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_support/usr/lib" \
    "$repo_root/Claude UsageTests/CodexAccountBindingTests.swift" \
    -o "$bundle/Contents/MacOS/CodexAccountBindingTests"

xcrun xctest "$bundle"
