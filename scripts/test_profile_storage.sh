#!/bin/bash
set -euo pipefail

# Run exact production persistence and Profile Codable code in an unhosted
# XCTest bundle. Injected synthetic stores and trapping test dependencies ensure
# no application startup, real Keychain, profile defaults, or provider access.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
developer_dir=$(xcode-select -p)
test_support="$developer_dir/Platforms/MacOSX.platform/Developer"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/claude-profile-storage-tests.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
bundle="$test_directory/StorageTests.xctest"
mkdir -p "$bundle/Contents/MacOS"

python3 - "$repo_root" "$test_directory" <<'PY'
from pathlib import Path
import sys

root, destination = map(Path, sys.argv[1:])
for filename in ('SecureProfilePersistenceTests.swift', 'ProfileStoreSecurityTests.swift'):
    source = (root / 'Claude UsageTests' / filename).read_text()
    (destination / filename).write_text(source.replace('@testable import Claude_Usage\n', ''))
PY

xcrun swiftc -emit-library -module-name StorageTests \
    -default-isolation MainActor \
    -DSECURE_PROFILE_ISOLATED_TESTS \
    -module-cache-path "$test_directory/module-cache" \
    -I "$test_support/usr/lib" \
    -F "$test_support/Library/Frameworks" \
    -L "$test_support/usr/lib" \
    -Xlinker -rpath -Xlinker "$test_support/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_support/usr/lib" \
    "$repo_root/Claude Usage/Shared/Storage/SecureProfilePersistence.swift" \
    "$repo_root/Claude Usage/Shared/Storage/ProfileStore.swift" \
    "$repo_root/Claude Usage/Shared/Models/Profile.swift" \
    "$repo_root/Claude Usage/Shared/Models/ProfileDisplayMode.swift" \
    "$repo_root/Claude UsageTests/ProfileStoreIsolatedTestSupport.swift" \
    "$test_directory/SecureProfilePersistenceTests.swift" \
    "$test_directory/ProfileStoreSecurityTests.swift" \
    -o "$bundle/Contents/MacOS/StorageTests"

xcrun xctest "$bundle"
