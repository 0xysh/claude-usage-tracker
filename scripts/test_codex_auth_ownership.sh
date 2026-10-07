#!/bin/bash
set -euo pipefail

# Compile the actual auth service in an isolated module, with synthetic stand-ins
# for app storage/logging. This never loads the app, login stores, or real auth.json.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
test_support="$developer_dir/Platforms/MacOSX.platform/Developer"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/codex-auth-ownership.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
bundle="$test_directory/CodexAuthOwnershipTests.xctest"
mkdir -p "$bundle/Contents/MacOS"

cat > "$test_directory/AppDependencies.swift" <<'SWIFT'
import Foundation

enum Provider { case codex }
struct Profile {
    let id = UUID()
    var name: String
    var provider: Provider
    var codexCredentialsJSON: String?
    init(name: String, provider: Provider, codexCredentialsJSON: String? = nil) {
        self.name = name
        self.provider = provider
        self.codexCredentialsJSON = codexCredentialsJSON
    }
}
struct AppError: Error {
    enum Code { case providerCredentialsNotFound, providerAuthExpired, providerAuthRefreshFailed, storageEncodingFailed, storageWriteFailed }
    let code: Code
    init(code: Code, message: String, technicalDetails: String? = nil,
         isRecoverable: Bool, recoverySuggestion: String? = nil) { self.code = code }
}
extension String { var localized: String { self } }
enum Constants { enum APIEndpoints { static let codexTokenRefresh = "https://auth.example.invalid/oauth/token" } }
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
    var profiles: [Profile] = []
    func updateProfile(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }
}
final class ProfileStore {
    static let shared = ProfileStore()
    var lastPersistenceError: Error? { preconditionFailure("Inject synthetic persistence") }
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
    "$repo_root/Claude Usage/Shared/Services/Providers/Codex/CodexAuthService.swift" \
    -o "$test_directory/libClaude_Usage.dylib"

xcrun swiftc -emit-library -module-name CodexAuthOwnershipTests -swift-version 5 \
    -module-cache-path "$test_directory/module-cache" \
    -I "$test_directory" -I "$test_support/usr/lib" \
    -F "$test_support/Library/Frameworks" \
    -L "$test_directory" -lClaude_Usage -L "$test_support/usr/lib" \
    -Xlinker -rpath -Xlinker "$test_directory" \
    -Xlinker -rpath -Xlinker "$test_support/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_support/usr/lib" \
    "$repo_root/Claude UsageTests/CodexAuthOwnershipTests.swift" \
    -o "$bundle/Contents/MacOS/CodexAuthOwnershipTests"

xcrun xctest "$bundle"
