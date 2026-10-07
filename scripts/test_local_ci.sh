#!/bin/bash
set -euo pipefail

# Local counterpart to build.yml. The unsigned Debug host gets a disposable
# bundle identifier because existing tests write UserDefaults.standard.
# Release keeps the app's normal identifier. Nothing is installed or opened.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
selected_developer_dir=${DEVELOPER_DIR:-}
allow_toolchain_mismatch=0

usage() {
    cat <<'USAGE'
Usage: scripts/test_local_ci.sh [--developer-dir PATH] [--allow-toolchain-mismatch]

Requires CI's Xcode 26.0.1 (17A400) by default. PATH selects Xcode for this
process only; it may name an Xcode.app or its Contents/Developer directory.
--allow-toolchain-mismatch explicitly permits a non-parity qualification run.
Logs, the test result bundle, and the universal Release app stay in build/.
LOCAL_CI_PACKAGES_DIR optionally selects a shared cache for the pinned packages.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --developer-dir)
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
            selected_developer_dir=$2
            shift 2
            ;;
        --allow-toolchain-mismatch)
            allow_toolchain_mismatch=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$selected_developer_dir" ]]; then
    if [[ -d /Applications/Xcode_26.0.1.app/Contents/Developer ]]; then
        selected_developer_dir=/Applications/Xcode_26.0.1.app/Contents/Developer
    else
        selected_developer_dir=$(/usr/bin/xcode-select -p)
    fi
fi
if [[ "$selected_developer_dir" == *.app ]]; then
    selected_developer_dir="$selected_developer_dir/Contents/Developer"
fi
[[ -x "$selected_developer_dir/usr/bin/xcodebuild" ]] || {
    printf 'Xcode developer directory is unavailable: %s\n' "$selected_developer_dir" >&2
    exit 2
}
export DEVELOPER_DIR="$selected_developer_dir"
unset TOOLCHAINS
xcode_version=$(/usr/bin/xcodebuild -version)
expected_version=$'Xcode 26.0.1\nBuild version 17A400'
qualification=ci-toolchain-parity
if [[ "$xcode_version" != "$expected_version" ]]; then
    if [[ "$allow_toolchain_mismatch" -ne 1 ]]; then
        printf 'Required CI toolchain is missing: Xcode 26.0.1 (17A400).\nSelected: %s\n%s\nNo builds or tests were started. Select the matching Xcode with --developer-dir.\n' \
            "$selected_developer_dir" "$xcode_version" >&2
        exit 2
    fi
    qualification=non-parity
    printf 'NON-PARITY qualification: selected Xcode differs from CI.\n%s\n' "$xcode_version"
fi

# Fail before launching the hosted runner if the scheme's lifecycle contract
# is removed. Normal LaunchAction and ProfileAction must not carry this marker.
python3 - "$repo_root/Claude Usage.xcodeproj/xcshareddata/xcschemes/Claude Usage.xcscheme" <<'PY'
import sys
import xml.etree.ElementTree as ET

scheme = ET.parse(sys.argv[1]).getroot()
test = scheme.find('TestAction')
marker = 'CLAUDE_USAGE_UNIT_TEST_HOST'
enabled = test is not None and test.get('shouldUseLaunchSchemeArgsEnv') == 'NO' and any(
    item.get('key') == marker and item.get('value') == '1' and item.get('isEnabled') == 'YES'
    for item in test.findall('./EnvironmentVariables/EnvironmentVariable')
)
normal_marker = any(item.get('key') == marker for action in ('LaunchAction', 'ProfileAction')
                    for item in scheme.findall(f'./{action}/EnvironmentVariables/EnvironmentVariable'))
if not enabled or normal_marker:
    sys.exit('Unsafe test-host scheme: require the lifecycle isolation marker only in TestAction.')
PY

mkdir -p "$repo_root/build"
run_directory=$(mktemp -d "$repo_root/build/local-ci.XXXXXX")
packages_directory=${LOCAL_CI_PACKAGES_DIR:-"$repo_root/build/local-ci-packages"}
mkdir -p "$packages_directory"
debug_identifier="com.0xysh.ClaudeUsage.LocalCI.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
printf 'Local gate: %s\nEvidence: %s\n' "$qualification" "$run_directory"
{
    printf 'Qualification: %s\nDeveloper directory: %s\nDebug preferences domain: %s\nPinned package cache: %s\n' \
        "$qualification" "$selected_developer_dir" "$debug_identifier" "$packages_directory"
    printf '%s\n' "$xcode_version"
    /usr/bin/xcrun swift --version
    /usr/bin/xcrun --sdk macosx --show-sdk-version
    /usr/bin/sw_vers
    git -C "$repo_root" rev-parse HEAD
    git -C "$repo_root" status --short
} > "$run_directory/environment.txt"

finish() {
    result=$?
    # Only the fresh Debug domain can be deleted; the production domain is
    # never read, backed up, reset, or restored by this runner.
    /usr/bin/defaults delete "$debug_identifier" >/dev/null 2>&1 || true
    printf 'Local gate exit: %s. Evidence retained: %s\n' "$result" "$run_directory"
}
trap finish EXIT

run_step() {
    local step_name=$1 timeout_seconds=$2
    shift 2
    python3 - "$run_directory" "$step_name" "$timeout_seconds" "$@" <<'PY'
from pathlib import Path
import os
import signal
import subprocess
import sys

directory, name, timeout, *command = sys.argv[1:]
log_path = Path(directory) / f'{name}.log'
print(f'{name}: running (log: {log_path})', flush=True)
with log_path.open('w') as output:
    process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        status = process.wait(timeout=int(timeout))
    except subprocess.TimeoutExpired:
        print(f'{name}: exceeded {timeout} seconds; terminating this build/test process group.', flush=True)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        status = 124
if status:
    print('\n'.join(log_path.read_text(errors='replace').splitlines()[-60:]), file=sys.stderr)
    sys.exit(status if status > 0 else 128 - status)
print(f'{name}: passed', flush=True)
PY
}

common=(
    -project "$repo_root/Claude Usage.xcodeproj"
    -scheme "Claude Usage"
    -derivedDataPath "$run_directory/DerivedData"
    -clonedSourcePackagesDirPath "$packages_directory"
    -disableAutomaticPackageResolution
    CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
)
debug=(-configuration Debug "PRODUCT_BUNDLE_IDENTIFIER=$debug_identifier")

run_step debug-build 1200 /usr/bin/xcodebuild build "${common[@]}" "${debug[@]}"
debug_app="$run_directory/DerivedData/Build/Products/Debug/Claude Usage.app"
actual_identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$debug_app/Contents/Info.plist")
[[ "$actual_identifier" == "$debug_identifier" ]] || {
    printf 'Refusing hosted tests: Debug preferences domain was not isolated.\n' >&2
    exit 1
}

run_step hosted-tests 300 /usr/bin/xcodebuild test "${common[@]}" "${debug[@]}" \
    -destination platform=macOS -resultBundlePath "$run_directory/TestResults.xcresult"
run_step release-build 1200 /usr/bin/xcodebuild build "${common[@]}" \
    -configuration Release 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO SWIFT_OPTIMIZATION_LEVEL=-O
release_app="$run_directory/DerivedData/Build/Products/Release/Claude Usage.app"
release_architectures=$(/usr/bin/xcrun lipo -archs "$release_app/Contents/MacOS/Claude Usage")
for required_architecture in arm64 x86_64; do
    [[ " $release_architectures " == *" $required_architecture "* ]] || {
        printf 'Release executable is missing architecture: %s\n' "$required_architecture" >&2
        exit 1
    }
done
printf 'PASS (%s): Debug build, full hosted test suite, optimized arm64/x86_64 Release build.\nRelease app: %s\n' \
    "$qualification" "$release_app"
