# Personal app delivery

The sufficient outcome is a locally signed macOS app from this fork, with the
existing Claude/Codex monitoring and owner-controlled feedback and updates,
installed in `/Applications` with normal GUI startup verified. The user
authorized installation and launch on 2026-10-07. Public release/notarization
and account login remain separate live steps.

Required fixes and gates:

- Replace plaintext credential fallback with verified, recoverable secure
  persistence. Preserve legacy data until secure migration succeeds.
- Treat profile names and saved statusline settings as data, never shell code.
- Make automatic Claude OAuth polling a read-only usage request. Do not generate
  a model response as a side effect of polling.
- Restrict credential-bearing Codex requests to official ChatGPT hosts over
  HTTPS and refuse redirects. Let Codex own refresh of its shared login file;
  continue refreshing manually managed profiles separately.
- Resolve the introduced CI failure with a reproduced cause, then run focused
  tests and the local CI gate on the handed-off source.
- Sign a local app with the available Apple Development identity and verify its
  complete bundle. This does not confer Developer ID notarization.

Automated tests use synthetic credentials and isolated stores only. Do not
perform normal app launch, alter existing installations, or connect live
accounts as part of automated validation. After validation, the separately
authorized delivery step installs the signed app and checks normal GUI startup.
Stop once the source, passing validation, installed signed app, startup result,
and exact remaining live verification requirements are handed off.

## Local validation gate

Run `scripts/test_local_ci.sh` before spending another GitHub Actions run. It
requires the workflow's Xcode 26.0.1 (17A400), builds unsigned Debug, runs the full
hosted XCTest suite with the shared scheme's isolated TestAction, then builds
optimized Release for both arm64 and x86_64 and verifies the executable slices.
Use `--developer-dir /path/to/Xcode.app` to select that toolchain for this process
without changing the machine's Xcode selection. A missing/mismatched toolchain
stops before building or launching tests.

Package versions come from the committed `Package.resolved`; automatic version
resolution is disabled. Set `LOCAL_CI_PACKAGES_DIR` to reuse an existing pinned
package cache (for example `/private/tmp/claude-personal-ownership-packages`).
The default shared cache is `build/local-ci-packages`. Initial pinned checkout
downloads may still require network access; this gate does not update versions.

`--allow-toolchain-mismatch` explicitly permits qualification with an available
Xcode while the matching toolchain is unavailable. Its result is labelled
**non-parity** and does not establish that GitHub's compiler/SDK will pass. Local
macOS and runner resources also differ from GitHub even with matching Xcode.

The Debug host uses a fresh bundle identifier because existing shared-store
tests write standard preferences. This deliberate difference from Actions
protects the installed app's preferences; Release retains its normal identity.
The runner verifies the Debug identifier before testing and removes only its
own disposable preferences domain afterward. The TestAction marker bypasses
the app's normal startup/termination, profiles, login loading, timers, and UI.
The full suite still exercises a loopback hook server (skipping a busy port),
synthetic temporary auth/files/defaults, and Keychain calls limited to fresh
test UUID accounts plus the synthetic `availability-probe` item. Unsigned hosts
refuse login-Keychain fallback; the two real secure-store round trips may skip.
This gate does not validate signed-app Keychain access or live provider accounts.

Each run keeps environment/source metadata, build/test logs, the xcresult
diagnostics bundle, and the unsigned Release app in a fresh ignored
`build/local-ci.*` directory. Hosted tests have a five-minute process timeout;
build steps have twenty-minute timeouts. Failed runs retain available evidence.
The gate performs no installation or normal app launch.

## Combined usage view

In Settings > Popover, enable **Show accounts together**. The accounts selected
in Manage Profiles appear in one scrollable popup, with Claude in green and Codex
in purple. The existing separate menu-bar icons remain available; either opens
the same combined popup. Disable this preference to restore individual popups.

Each card uses its own profile's readings and errors. Missing readings show
Unavailable, failed refreshes or readings older than five minutes show Last known,
and recent successful readings show Fresh. The used/remaining label follows the
existing percentage preference. The popup's **Used % / Remaining %** switch changes all cards together and saves
the existing multi-profile percentage preference. In multi-profile mode it also
updates the menu-bar percentages. It changes presentation only. A reported Fable
quota appears even at zero; missing or invalid Fable data is labelled No quota
reported. Neither state invents
a usage value. TwinQuota informed the visual layout only; polling endpoints and
the counter-reading method remain this fork's existing implementation.

File-backed Codex profiles bind to a nonsecret account identity only after a
successful fetch while that profile is active. For an older unbound profile,
select it and use **Test Connection** once. Later combined/background reads must
match that identity. A changed Codex login requires reconnecting the intended
account; this app never rewrites or rotates the shared Codex login file.

Claude refreshes use the same profile-aware credential selector in individual
and combined views. Expired or incomplete CLI credentials produce an explicit
error while preserving the last reading. Reconnect and sync through Claude Code
when prompted. Browser organization discovery uses only the requested profile's
session, and an in-flight response cannot be saved into a newly active profile.

The focused synthetic regressions cover zero/missing Fable quotas, account
binding and mismatches, Claude source selection, browser organization isolation,
and freshness/error states. Full local qualification runs with the lifecycle
and preferences isolation described above. Embedded-browser login repair and
TwinQuota's counter-reading or crash behavior are outside this change.
