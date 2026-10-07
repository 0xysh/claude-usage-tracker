#!/bin/bash
set -euo pipefail

# Local Apple Development packaging. Does not install, launch, notarize, or publish.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
signing_identity=${1:?Pass the public SHA-1 identifier of your Apple signing identity.}
if [[ ! "$signing_identity" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    echo 'Expected a public certificate identity identifier.' >&2
    exit 1
fi
build_directory=${PERSONAL_BUILD_DIR:-"$repo_root/build/personal"}
packages_directory=${PERSONAL_PACKAGES_DIR:-"$repo_root/build/personal-packages"}
output_directory="$repo_root/release/personal"
mkdir -p "$output_directory"

xcodebuild build \
    -project "$repo_root/Claude Usage.xcodeproj" -scheme 'Claude Usage' \
    -configuration Release -derivedDataPath "$build_directory" \
    -clonedSourcePackagesDirPath "$packages_directory" \
    -disableAutomaticPackageResolution \
    CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

app="$output_directory/Claude Usage.app"
if [ -e "$app" ]; then
    echo 'Existing personal app preserved; move it before packaging a replacement.' >&2
    exit 1
fi
ditto "$build_directory/Build/Products/Release/Claude Usage.app" "$app"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
if [ "$bundle_id" != 'com.0xysh.ClaudeUsage' ]; then
    echo 'Refusing to package an app with another distribution identity.' >&2
    exit 1
fi

# Sign nested executable code from the inside out; preserve framework structure.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
for component in \
    "$sparkle/Versions/B/XPCServices/Installer.xpc" \
    "$sparkle/Versions/B/XPCServices/Downloader.xpc" \
    "$sparkle/Versions/B/Autoupdate" \
    "$sparkle/Versions/B/Updater.app" \
    "$sparkle"; do
    codesign --force --sign "$signing_identity" --timestamp=none --options runtime "$component"
done
codesign --force --sign "$signing_identity" --timestamp=none --options runtime \
    --entitlements "$repo_root/Claude Usage/Claude UsageRelease.entitlements" "$app"
codesign --verify --deep --strict "$app"

archive="$output_directory/Claude-Usage-personal.zip"
if [ -e "$archive" ]; then
    echo 'Existing archive preserved; move it before packaging a replacement.' >&2
    exit 1
fi
ditto -c -k --keepParent "$app" "$archive"
(cd "$output_directory" && shasum -a 256 Claude-Usage-personal.zip > Claude-Usage-personal.zip.sha256)
printf 'Personal app created: %s\n' "$app"
