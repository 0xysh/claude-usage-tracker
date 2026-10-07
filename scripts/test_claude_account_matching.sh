#!/bin/bash
set -euo pipefail

# Compile the real CLI service and run only its pure synthetic account checks.
# All application persistence is trapped; no credential accessor is invoked.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
test_support="$developer_dir/Platforms/MacOSX.platform/Developer"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/claude-account-matching.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
bundle="$test_directory/ClaudeCLICredentialMatchTests.xctest"
mkdir -p "$bundle/Contents/MacOS"

cat > "$test_directory/AppDependencies.swift" <<'SWIFT'
import Foundation
struct Profile {
    var id = UUID()
    var name: String
    var cliCredentialsJSON: String?
    var customKeychainServiceName: String?
    var oauthAccountJSON: String?
    var cliAccountSyncedAt: Date?
    init(name: String, cliCredentialsJSON: String? = nil, oauthAccountJSON: String? = nil) {
        self.name = name
        self.cliCredentialsJSON = cliCredentialsJSON
        self.oauthAccountJSON = oauthAccountJSON
    }
}
final class ProfileStore {
    static let shared = ProfileStore()
    func loadProfiles() -> [Profile] { preconditionFailure("A pure identity check must not access storage") }
    func loadActiveProfileId() -> UUID? { preconditionFailure("A pure identity check must not access storage") }
    func saveProfiles(_ profiles: [Profile]) { preconditionFailure("A pure identity check must not write storage") }
}
final class LoggingService {
    static let shared = LoggingService()
    func log(_ message: String) {}
    func logError(_ message: String, error: Error? = nil) {}
}
enum Constants {
    enum ClaudePaths {
        static let claudeDirectory = URL(fileURLWithPath: "/nonexistent-synthetic-test-home")
        static let credentialsFile = claudeDirectory.appendingPathComponent("credentials.json")
        static let claudeConfigCandidates: [URL] = []
    }
}
SWIFT

xcrun swiftc -emit-library -emit-module -enable-testing -module-name Claude_Usage \
    -swift-version 5 -default-isolation MainActor \
    -module-cache-path "$test_directory/module-cache" \
    -emit-module-path "$test_directory/Claude_Usage.swiftmodule" \
    "$test_directory/AppDependencies.swift" \
    "$repo_root/Claude Usage/Shared/Services/ClaudeCodeSyncService.swift" \
    -o "$test_directory/libClaude_Usage.dylib"

xcrun swiftc -emit-library -module-name ClaudeCLICredentialMatchTests -swift-version 5 \
    -module-cache-path "$test_directory/module-cache" \
    -I "$test_directory" -I "$test_support/usr/lib" \
    -F "$test_support/Library/Frameworks" \
    -L "$test_directory" -lClaude_Usage -L "$test_support/usr/lib" \
    -Xlinker -rpath -Xlinker "$test_directory" \
    -Xlinker -rpath -Xlinker "$test_support/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_support/usr/lib" \
    "$repo_root/Claude UsageTests/ClaudeCLICredentialMatchTests.swift" \
    -o "$bundle/Contents/MacOS/ClaudeCLICredentialMatchTests"

xcrun xctest "$bundle"
