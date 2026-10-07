#!/bin/bash
set -euo pipefail

# Exercise the exact production selector with synthetic source/persistence/
# transport adapters. Extracting this one method avoids linking real accessors.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/claude-background-polling.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT

python3 - "$repo_root" "$test_directory" <<'PY'
import pathlib
import sys

source = (pathlib.Path(sys.argv[1]) / "Claude Usage/Shared/Services/ClaudeCodeSyncService.swift").read_text()

def method(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]

selectors = [
    "func ensureFreshCredentials(", "func systemCredentialsMatchProfile(",
    "func accountIdentity(", "func extractRefreshToken(",
    "func extractTokenExpiry(", "func isTokenExpired(",
]
prefix = r'''
import Foundation
struct Profile {
    let id = UUID()
    let name = "Synthetic"
    var customKeychainServiceName: String? = nil
    var cliCredentialsJSON: String?
    var oauthAccountJSON: String?
}
final class ProfileStore {
    static let shared = ProfileStore()
    var profiles: [Profile] = []
    var activeID: UUID?
    func loadProfiles() -> [Profile] { profiles }
    func loadActiveProfileId() -> UUID? { activeID }
}
final class LoggingService {
    static let shared = LoggingService()
    func log(_ message: String) {}
    func logError(_ message: String, error: Error? = nil) {}
}
enum ClaudeCodeError: Error { case refreshFailed(Int, String) }
final class SyntheticSelector {
    typealias OAuthRefreshResponse = String
    static let refreshLeewaySeconds: TimeInterval = 60
    var systemJSON: String
    var systemAccountJSON = "{\"accountUuid\":\"synthetic-account-a\"}"
    var refreshCount = 0
    var systemWriteCount = 0
    var mirrorWriteCount = 0
    init(systemJSON: String) { self.systemJSON = systemJSON }
    func readSystemCredentials() throws -> String? { systemJSON }
    func readOAuthAccount() -> String? { systemAccountJSON }
    func readKeychainCredentials(serviceName: String) -> String? { systemJSON }
    func performTokenRefresh(refreshToken: String) async throws -> String {
        refreshCount += 1
        return "{\"claudeAiOauth\":{\"accessToken\":\"synthetic-new-access\",\"refreshToken\":\"synthetic-new-lineage\",\"expiresAt\":4102444800000}}"
    }
    func mergeRefreshedCredentials(into json: String, refreshed: String) -> String? { refreshed }
    func writeSystemCredentials(_ json: String) throws { systemWriteCount += 1; systemJSON = json }
    func writeCredentialsFile(_ json: String) { mirrorWriteCount += 1 }
    func writeKeychainCredentials(serviceName: String, jsonData: String) throws { systemWriteCount += 1 }
    func persistProfileCredentialsJSON(profileId: UUID, json: String) {
        guard let index = ProfileStore.shared.profiles.firstIndex(where: { $0.id == profileId }) else { return }
        ProfileStore.shared.profiles[index].cliCredentialsJSON = json
    }
'''
suffix = r'''
}
@main struct Regression {
    static func main() async {
        let expired = "{\"claudeAiOauth\":{\"accessToken\":\"synthetic-expired\",\"refreshToken\":\"synthetic-lineage\",\"expiresAt\":1000}}"
        let account = "{\"accountUuid\":\"synthetic-account-a\"}"
        let profile = Profile(cliCredentialsJSON: expired, oauthAccountJSON: account)
        var failures = 0
        func check(_ passed: Bool, _ name: String) {
            print("\(passed ? "PASS" : "FAIL") \(name)")
            if !passed { failures += 1 }
        }
        ProfileStore.shared.profiles = [profile]
        ProfileStore.shared.activeID = profile.id
        let background = SyntheticSelector(systemJSON: expired)
        let result = await background.ensureFreshCredentials(for: profile.id, allowRotation: false)
        check(background.refreshCount == 0 && background.systemWriteCount == 0 && background.mirrorWriteCount == 0,
              "background polling never rotates or writes system credentials")
        check(result == expired && ProfileStore.shared.profiles[0].cliCredentialsJSON == expired,
              "background polling retains the expired snapshot for an explicit login error")
        ProfileStore.shared.profiles = [profile]
        let explicit = SyntheticSelector(systemJSON: expired)
        _ = await explicit.ensureFreshCredentials(for: profile.id, allowRotation: true)
        check(explicit.refreshCount == 1 && explicit.systemWriteCount == 1 && explicit.mirrorWriteCount == 1,
              "explicit activation retains the existing refresh and write-back policy")
        var pinnedProfile = profile
        pinnedProfile.customKeychainServiceName = "synthetic-keychain-entry"
        ProfileStore.shared.profiles = [pinnedProfile]
        ProfileStore.shared.activeID = UUID()
        let pinned = SyntheticSelector(systemJSON: expired)
        let pinnedResult = await pinned.ensureFreshCredentials(for: pinnedProfile.id, allowRotation: false)
        check(pinned.refreshCount == 0 && pinned.systemWriteCount == 0,
              "pinned background polling never rotates or writes credentials")
        check(pinnedResult == expired,
              "pinned background polling retains the expired snapshot for a login error")
        exit(failures == 0 ? 0 : 1)
    }
}
'''
destination = pathlib.Path(sys.argv[2]) / "Regression.swift"
destination.write_text(prefix + "\n".join(method(signature) for signature in selectors) + suffix)
PY

xcrun swiftc -swift-version 5 -parse-as-library \
    -module-cache-path "$test_directory/module-cache" \
    "$test_directory/Regression.swift" -o "$test_directory/Regression"
"$test_directory/Regression"
