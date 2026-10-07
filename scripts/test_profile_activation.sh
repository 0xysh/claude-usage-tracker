#!/bin/bash
set -euo pipefail

# Compile the complete, unmodified production manager and model against memory-
# only dependencies. This exercises activation without touching real accounts.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
test_support="$developer_dir/Platforms/MacOSX.platform/Developer"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/profile-activation.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
bundle="$test_directory/ProfileActivationTests.xctest"
mkdir -p "$bundle/Contents/MacOS"

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
    "$repo_root/scripts/tests/ProfileActivationDependencies.swift" \
    "$repo_root/Claude Usage/Shared/Models/Profile.swift" \
    "$repo_root/Claude Usage/Shared/Services/ProfileManager.swift" \
    -o "$test_directory/libClaude_Usage.dylib"

xcrun swiftc -emit-library -module-name ProfileActivationTests -swift-version 5 \
    -module-cache-path "$test_directory/module-cache" \
    -I "$test_directory" -I "$test_support/usr/lib" \
    -F "$test_support/Library/Frameworks" \
    -L "$test_directory" -lClaude_Usage -L "$test_support/usr/lib" \
    -Xlinker -rpath -Xlinker "$test_directory" \
    -Xlinker -rpath -Xlinker "$test_support/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_support/usr/lib" \
    "$repo_root/scripts/tests/ProfileActivationTests.swift" \
    -o "$bundle/Contents/MacOS/ProfileActivationTests"

xcrun xctest "$bundle"
