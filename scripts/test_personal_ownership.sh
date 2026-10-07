#!/bin/bash
set -euo pipefail

# Run only the ownership tests in an unhosted XCTest bundle. The app's startup,
# profile loading, login stores, provider requests, and browser are never run.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
developer_dir=$(xcode-select -p)
test_support="$developer_dir/Platforms/MacOSX.platform/Developer"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/claude-ownership-tests.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
bundle="$test_directory/OwnershipTests.xctest"
mkdir -p "$bundle/Contents/MacOS"

python3 - "$repo_root" "$test_directory" <<'PY'
from pathlib import Path
import sys

root, destination = map(Path, sys.argv[1:])
for filename in ('HeartbeatServiceTests.swift', 'FeedbackIssueURLTests.swift'):
    source = (root / 'Claude UsageTests' / filename).read_text()
    # Compile the exact production files beside these tests, without loading the
    # application's executable module or its hosted test runner.
    (destination / filename).write_text(source.replace('@testable import Claude_Usage\n', ''))
PY

xcrun swiftc -emit-library -module-name OwnershipTests \
    -module-cache-path "$test_directory/module-cache" \
    -I "$test_support/usr/lib" \
    -F "$test_support/Library/Frameworks" \
    -L "$test_support/usr/lib" \
    -Xlinker -rpath -Xlinker "$test_support/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_support/usr/lib" \
    "$repo_root/Claude Usage/Shared/Services/HeartbeatService.swift" \
    "$repo_root/Claude Usage/Shared/Utilities/FeedbackIssueURL.swift" \
    "$test_directory/HeartbeatServiceTests.swift" \
    "$test_directory/FeedbackIssueURLTests.swift" \
    -o "$bundle/Contents/MacOS/OwnershipTests"

xcrun xctest "$bundle"
