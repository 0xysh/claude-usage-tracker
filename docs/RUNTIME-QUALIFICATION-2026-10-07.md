# Supplementary installed-app qualification — 2026-10-07

Scope: verify the existing personal installation, bounded real-machine runtime,
and the remaining interaction/recovery gates. Widgets are excluded. The subsequent
reported empty-space issue adds a focused content-size correction. Account
credentials and animation policy remain unchanged. The bounded connectivity check
restores the original Wi-Fi state; it does not alter stored network configuration.
The user explicitly requested that normal animation remain enabled; the system
Reduce Motion preference was not changed and its native toggle check is withdrawn.

## Current installed artifact

- Installed bundle: `/Applications/Claude Usage.app`, `com.0xysh.ClaudeUsage`, 3.3.0.
- Runtime source: `63fd22f1d1c3118fb30327138b9972efe9970df4`.
- Repository HEAD at check start: `265a0f32b2b8ffd0686ee867431a77d5a7deaf98`;
  the baseline installation then had source `7aa7802d32716b2bead5ff5733ce6b20279c36a4`.
- Executable SHA-256: `f4898a8aa19119f25a2dadb5885446fe8dd8bc75b36e1b5b25ecfa725c8da940`.
- ZIP SHA-256: `c95fedb72a5d8535a8220e3fc8e4c7a569319a3a9c556465611a346cf5087f62`.
- Universal optimized executable: arm64 and x86_64.
- Fresh strict nested signing verification passed on the installed bundle.
- Host: macOS 27.2 (26B5091g), Xcode 27.0 beta (27A5228h).
  This remains non-parity with the unavailable CI Xcode 26.0.1.

## Focused automated gate

Fresh isolated hosted run: **77 passed, 0 failed, 0 skipped**.
The disposable preferences domain was removed by the runner. The production
preferences domain and account credentials were not read, reset or changed.

Suites: `UsageDataStateTests`, `MenuBarUsagePresentationTests`, `UsageMotionTests`,
`CombinedStatusBarLifecycleTests`, `NSWindowFullScreenSpacesTests`,
`CombinedMenuBarPresentationTests`, `AnthropicUsageProviderTests`,
`CodexProviderTests`. These check cached/missing/future readings, used/remaining
presentation, numeric/fill geometry, status-item lifecycle, provider mapping,
and account-selection failure handling. Geometry tests for accessibility policy
do not change the user's system setting.

Evidence: ignored `build/runtime-qualification/FocusedTests.xcresult`,
`test-summary.json`, `test-environment.json`, `focused-tests.log`.
The subsequent final gate on the corrected source passes Debug build, full hosted
tests and optimized arm64/x86_64 Release build: **384 total, 382 passed, 0 failed,
2 skipped**. The skips are the existing unsigned-host Keychain tests. Evidence:
ignored `build/local-ci.ZCzfQ5/TestResults.xcresult`,
`build/runtime-qualification/final-test-summary.json`,
`final-local-ci-corrected.log`. This is local toolchain validation, not a claim
of equivalence to the unavailable CI Xcode 26.0.1.

## Bounded installed runtime

On the baseline source `7aa7802`, the six-minute probe samples numeric process accounting at 1 Hz and
keeps the exact installed PID under observation. Two self-limiting CPU workers
run for 120 seconds within that window. Reopening through LaunchServices checks
that the existing process presents one dashboard rather than duplicating it.
These are reopen requests, not mouse close/reopen or dragging interactions.
The first own-window screenshot confirms both providers display fresh readings.

Evidence: ignored `build/runtime-qualification/installed-runtime.csv`,
`installed-runtime.json`, `runtime_probe.py`; local screenshot
`/private/tmp/claude-polish-audit/runtime-qualified-popup-start.png`.
All **360 samples** and four reopen observations were collected. The same exact
installed PID remained alive through the controlled load. Workers each used about
104 CPU seconds within 120 wall seconds. Physical footprint medians were 44.44 MiB
before load, 42.84 MiB during load, and 43.08 MiB afterward; the maximum across the
last phase was 61.25 MiB. This short observation does not establish leak freedom,
absence of hangs or prolonged heavy-load reliability.

The probe exited on its final popup-visible assertion: that last observer saw
zero visible windows while the same process was still running. The dismissal
cause was not observed. The failed assertion and original evidence are preserved;
it is not recast as a fully passing UI gate. Only process continuity, completed
accounting and the four one-window reopen observations are established.
Summary: ignored `build/runtime-qualification/runtime-summary.json`.

## Content-fit regression

The user's subsequent screenshot reproduced an empty area below the final card.
`CombinedUsageView` reserved the screen cap (680 points on this host) regardless
of the actual header and card-stack height. Three new native hosting tests failed
with that exact 680-point value for short/empty content and size transitions.

The correction measures the intrinsic header and card stack independently of the
scroll viewport, rounds stable measurements up, and caps the resulting frame at
the existing screen limit. Long content still scrolls. Native window sizing remains
unanimated while quota animations remain enabled. A detached panel receives the
same measured height, keeping its top edge and existing no-sizingOptions contract.
Its reference is stored before attaching the hosting controller so the first
measurement callback can resize it.

The first corrected native-hosting run passes all three tests. Evidence is
`build/runtime-qualification/sizing-{red,green}.xcresult`; the red summary confirms
expected assertion failures rather than compile/runner errors. These three cases
also pass in the final full gate. A focused independent review found a detached
callback ownership issue, corrected before that final gate; the subsequent review
found no remaining source-level blocker.

The signed corrected app is installed and running from `/Applications/Claude Usage.app`.
Installer evidence: `build/runtime-qualification/install-content-fit.log`.
The on-screen popup is 386 by 652 points, down from the baseline's 386 by 706.
Its content height is 626 points; the final card now has the intended bottom
padding without the previous 54-point surplus. Own-window screenshot:
`/private/tmp/claude-polish-audit/content-fit-cached-window.png`.

After reopening the exact installed app, five own-window frames show stable
652-point height throughout the entrance. Visible counters progress from
9 to 14 to 16 percent (Codex), 59 to 92 to 100 percent (Claude weekly), and
14 to 23 to 25 percent (extra usage); fills grow with the counters and intermediate
digits are blurred. Evidence: local `content-fit-opening-fast/frame-{0,1,4}.png`
and `timings.json` under `/private/tmp/claude-polish-audit/`. Capture timestamps
bound capture calls, not individual display frames. This establishes actual
interpolation continuity during this opening, not every interaction scenario.
The first slower screenshot sequence sampled after the sweep had finished;
it is retained as settled-layout evidence only.

An initial bare-path LaunchServices reopen request did not expose an on-screen
popup while the exact process stayed alive. Explicit `open -a` succeeded; controlled
fresh-process reopen captures subsequently succeeded. The initial observation is
preserved and is not attributed to a source defect without further evidence.

## Bounded network recovery on the corrected installation

Original Wi-Fi power was On; an idempotent On request first verified the available
setting permission. A separate restore watchdog was armed before a 35-second Off
interval, and the main probe restored On in its finally block. No stored network
configuration or credentials were changed. The same installed PID remained alive.
The disconnected capture shows Saved for both accounts and existing quota rows;
the restored capture, 12 seconds after reconnection, shows both Fresh at nine
seconds. The filtered app log recorded one `Network became available` event.
No manual Refresh or account reconnection was used.

The same popup window grew from 652 to the 706-point screen cap when connection
help rows appeared, with a visible scroll track, then shrank back to 652 after
recovery. This closes this bounded disconnect/reconnect and live sizing-transition
check. It does not qualify every network, captive portal or repeated outage.

Evidence: ignored `build/runtime-qualification/network-recovery.json` and
`network_recovery_probe.py`; local `network-recovery/{before,offline,recovered}.png`
under `/private/tmp/claude-polish-audit/`. The offline image was captured while its
reopening counter animation was in progress, so its intermediate percentages are
not treated as new provider readings. An earlier probe stopped before disconnect
because its initial popup-visible precondition failed; original code is retained
as `network_recovery_probe-before-guard.py`. The corrected observer explicitly
opens the app for each snapshot, and failure cleanup preserves the restore guard.

## Native interaction limits and recovery review

Computer Use could not bind the installed accessory app: the exact installed
path returned `-10005: timeoutReached` despite the real popup being visible in
the own-process window observer. A System Settings attempt also stalled, then
returned `App quit` on navigation; no system preference was changed. These tool
failures are not evidence that Claude Usage crashed.

The following native gates remain **unqualified**: repeated mouse/keyboard
close and reopen, actual drag detachment and return, focus/VoiceOver interaction,
physical sleep/wake. Source/unit evidence below does not close these gates.
The normal animation setting remains unchanged. Automatic wake scheduling could
not be prepared with available privileges (`sudo -n` requires a password); no
physical sleep was initiated without a verified bounded wake plan.

Reviewed recovery paths: `MenuBarManager.setupWakeObserver()` debounces wakes
within ten seconds of an automatic refresh and delays the subsequent refresh by
three seconds. `NetworkMonitor` calls back on disconnected-to-connected changes,
then the manager debounces that trigger by two seconds. During an existing refresh
new triggers are rejected; recovery then depends on the next timer/manual refresh.
Cached usage is retained on provider failure and marked last-known; success clears
the per-profile error. There are no direct tests of the OS notification/path events.
This review identifies a native check target, not a reproduced defect.

## Backup readiness

The existing origin was verified live as the public fork
`0xysh/claude-usage-tracker`; its personal branch matched the checked HEAD.
A verified local Git bundle contains both local branches and their reachable
history: ignored `build/runtime-qualification/personal-source-backup-content-fit.bundle`.
`backup-readiness-content-fit.json` identifies that bundle, its exact HEAD,
the final ZIP/checksum and the personal build receipt. The original baseline bundle
and readiness snapshot remain preserved separately. None has been uploaded to a
new destination.

Recommendation awaiting creation authorization: an independent private repository
alongside the public fork, Actions disabled before any source push, personal
branch as its default, source history plus the verified ZIP/checksum/receipt.
Keep MIT attribution intact. Signing private keys require a separate encrypted
backup and must not be placed in Git or release attachments. A source repository
does not back up app credentials, preferences, Apple signing identities or ignored
build/output directories.

No GitHub Actions run was started. No new repository was created during preparation.
