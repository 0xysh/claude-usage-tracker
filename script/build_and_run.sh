#!/bin/bash
set -euo pipefail

# Build and sign the personal app, then launch its bundle. Installation is opt-in.
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bundle_id='com.0xysh.ClaudeUsage'
output_directory="$repo_root/release/personal"
app="$output_directory/Claude Usage.app"
installed_app='/Applications/Claude Usage.app'
install=0
verify=0

usage() {
    printf 'Usage: %s [run] [--install] [--verify]\n' "$0"
    printf 'Signing: PERSONAL_SIGNING_IDENTITY or .private/signing-identity (public certificate SHA-1).\n'
}

for argument in "$@"; do
    case "$argument" in
        run) ;;
        --install) install=1 ;;
        --verify) verify=1 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

fail() { printf '%s\n' "$1" >&2; exit 1; }

is_owned_bundle() {
    local identifier
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null) || return 1
    [[ "$identifier" == "$bundle_id" ]]
}

# Select only processes executing this exact bundle's main executable, never
# another distribution with the same display/process name.
app_pids() {
    local executable="$1/Contents/MacOS/Claude Usage"
    [[ -f "$executable" ]] || return 0
    /usr/sbin/lsof -a -d txt -t -- "$executable" 2>/dev/null || true
}

stop_owned_bundle() {
    local bundle="$1" pid attempt
    is_owned_bundle "$bundle" || return 0
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -TERM "$pid" 2>/dev/null || true
    done < <(app_pids "$bundle")
    for ((attempt=0; attempt<20; attempt++)); do
        [[ -n "$(app_pids "$bundle")" ]] || return 0
        sleep 0.25
    done
    fail "The personal app did not stop. Quit it before rebuilding: $bundle"
}

signing_identity=${PERSONAL_SIGNING_IDENTITY:-}
if [[ -z "$signing_identity" && -f "$repo_root/.private/signing-identity" ]]; then
    signing_identity=$(cat "$repo_root/.private/signing-identity")
fi
[[ "$signing_identity" =~ ^[0-9A-Fa-f]{40}$ ]] || fail 'Set a public Apple signing certificate SHA-1 in PERSONAL_SIGNING_IDENTITY or .private/signing-identity.'

if [[ -e "$app" || -L "$app" ]]; then
    [[ ! -L "$app" ]] && is_owned_bundle "$app" || fail 'Refusing to replace a personal output bundle with an unexpected identity or symbolic link.'
fi
if ((install)) && [[ -e "$installed_app" || -L "$installed_app" ]]; then
    [[ ! -L "$installed_app" ]] && is_owned_bundle "$installed_app" || fail 'The installation target belongs to another app. It has been preserved.'
fi

stop_owned_bundle "$app"
if [[ ! -L "$installed_app" ]]; then stop_owned_bundle "$installed_app"; fi

# The packager deliberately refuses overwrite. Preserve all previous artifacts
# under a fresh directory before invoking that one authoritative build/sign path.
mkdir -p "$output_directory/backups"
backup_directory=''
for artifact in "$app" "$output_directory/Claude-Usage-personal.zip" "$output_directory/Claude-Usage-personal.zip.sha256" "$output_directory/BUILD-RECEIPT.md"; do
    if [[ -e "$artifact" || -L "$artifact" ]]; then
        if [[ -z "$backup_directory" ]]; then
            backup_directory=$(mktemp -d "$output_directory/backups/build-$(date +%Y%m%d-%H%M%S)-XXXXXX")
        fi
        mv "$artifact" "$backup_directory/"
    fi
done
if [[ -n "$backup_directory" ]]; then printf 'Previous build preserved: %s\n' "$backup_directory"; fi

"$repo_root/scripts/package_personal_app.sh" "$signing_identity"
is_owned_bundle "$app" || fail 'The newly packaged bundle has an unexpected identity.'
/usr/bin/codesign --verify --deep --strict "$app"
launch_app="$app"

if ((install)); then
    # Stage and verify the copy before moving any existing owned installation.
    staging_directory=$(mktemp -d '/Applications/.ClaudeUsage-personal-XXXXXX')
    staged_app="$staging_directory/Claude Usage.app"
    trap '/bin/rm -rf "$staging_directory"' EXIT
    /usr/bin/ditto "$app" "$staged_app"
    is_owned_bundle "$staged_app" || fail 'The staged installation has an unexpected identity.'
    /usr/bin/codesign --verify --deep --strict "$staged_app"
    if [[ -e "$installed_app" || -L "$installed_app" ]]; then
        [[ ! -L "$installed_app" ]] && is_owned_bundle "$installed_app" || fail 'The installation target changed to another app. It has been preserved.'
        stop_owned_bundle "$installed_app"
        install_backup=$(mktemp -d "$output_directory/backups/install-$(date +%Y%m%d-%H%M%S)-XXXXXX")
        mv "$installed_app" "$install_backup/"
        printf 'Previous installation preserved: %s\n' "$install_backup"
    fi
    [[ ! -e "$installed_app" && ! -L "$installed_app" ]] || fail 'The installation target is occupied. It has been preserved.'
    mv "$staged_app" "$installed_app"
    rmdir "$staging_directory"
    trap - EXIT
    launch_app="$installed_app"
fi

/usr/bin/open -n "$launch_app"
printf 'Launched personal app: %s\n' "$launch_app"

if ((verify)); then
    for ((attempt=0; attempt<40; attempt++)); do
        if [[ -n "$(app_pids "$launch_app")" ]]; then
            printf 'Verified a running process from: %s\n' "$launch_app"
            exit 0
        fi
        sleep 0.25
    done
    fail 'The app launch was requested, but its exact executable was not observed running.'
fi
