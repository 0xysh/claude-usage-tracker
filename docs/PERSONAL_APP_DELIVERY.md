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
