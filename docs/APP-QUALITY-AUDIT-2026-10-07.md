# Personal app quality audit — 2026-10-07

## Delivery contract

Refine the existing native app and its complete account → usage → recovery path.
Keep this fork's provider-reading method, shared Codex auth-file ownership,
local reporting, owned feedback/update destinations, and upstream attribution.
The supplied menu-bar screenshot is the starting defect evidence. TwinQuota
remains a visual reference only.
The user's follow-up screenshot additionally requires one native menu-bar item
for all selected providers, with a readable horizontal summary inspired by
TwinQuota. This extends the delivery gate to native item lifecycle/identity,
weekly/Fable rendering, and separate-mode restoration.

Required gates: reproduce and fix verified account/data defects, inspect actual
SwiftUI renders with synthetic edge cases, pass focused regressions and the full
isolated local test/optimized universal Release gate, sign/install/launch the
personal app, and record remaining live verification limits. No GitHub Actions
run is needed. Stop after those gates; this is not an unbounded feature rewrite.

## Findings and corrections

| Priority | Verified defect | Correction | Evidence |
|---|---|---|---|
| P1 | Claude's selector equated missing refresh-token lineages, potentially accepting a different system account | Require matching known identities or nonempty matching lineage; conflicting known identities are authoritative | Exact selector regression: 5 failures before, 8 tests pass after |
| P1 | Active/pinned Claude polling could rotate CLI credentials despite `allowRotation=false` | Background reads retain the snapshot; only explicit activation may rotate | Exact-method regression: 4 failures before, 5 controls pass after |
| P1 | Profile activation re-saved the pre-refresh profile, replacing newly rotated credentials/metadata | Commit the latest target after refresh; abort if that target was removed | Complete manager/model synthetic regression: 3 failing tests/10 assertions before, 5 tests pass after |
| P1 | Joined manual Codex refreshes updated only the first profile, asynchronously, and could overwrite replacement credentials | Each caller awaits its own current-source-checked secure commit; obsolete results and persistence failures surface errors | Exact-source regression: 5 failing assertions before, 10 tests pass after |
| P2 | Invalid/missing Codex windows became fresh 0%; empty usage could bind an account | Validate finite nonnegative percentages, preserve a valid counterpart, mark absent metrics unavailable, reject wholly unusable responses before binding | Provider/DTO/model regressions: 21 failing assertions before; focused suite passes after |
| P2 | Unknown Claude usage replaced both reading and account identity with a question mark | Keep the profile label with an em dash, plus an explicit accessible explanation | Supplied screenshot, renderer and presentation regressions |
| P2 | Saved menu-bar readings could appear healthy and fresh | Neutral cached readings, a clock, freshness/error tooltip and VoiceOver description | Actual renderer fixtures in both appearances |
| P2 | Cached session usage became zero solely because its old reset date passed | Preserve the last measured value while stale; label past resets as reported dates | Presentation regression and saved-reading render |
| P2 | Future-dated/missing legacy timestamps could become fresh | Bound clock skew; missing timestamps decode as old, absent windows stay unavailable | Failing future-date regression before fix; state/cache tests after |
| P2 | Individual refresh spinner stopped after an arbitrary second | Use the actual refresh lifecycle; per-account actions refresh the named account | Source inspection; hosted compilation and presentation validation |
| P2 | Recovery opened generic appearance settings rather than the affected account | Connect account selects that profile and opens its provider's credential section | Source routing inspection; live UI verification recorded below |
| P2 | Percentage switch in a combined popup did not update single-profile icons consistently | Apply the same app-wide combined preference and avoid calling multi-mode configuration from single-mode notifications | Source flow inspection and full local qualification |
| P2 | Detached combined content used an individual window's 280-point width | Size the detached window for the combined view | Source sizing inspection; live detachment remains a manual gate |
| P2 | The installed popup's expanded recovery copy and secondary account data pushed the other provider below the useful overview | Compact primary rows; keep Fable visible; collapse connection help and plan/credits into details | Actual installed screenshot exposed the defect; two-provider render height falls from 851 to 527 points, with 120 reserved for header/mode picker |
| P2 | Shared popup still created two separate provider menu items | One owned native item with stable autosave/width and readable provider/period/percentage segments, including Fable | Native lifecycle regression verifies 1 item for 2 accounts, same button/width after refresh and percentage toggle, 2 items after separate-mode restoration and 0 after cleanup |
| P2 | Keyboard/reopen fallback returned nil when the active profile had no selected item or the default logo was used | Prefer the combined item, then actual configured/default/ordered selected-profile buttons | Actual reopen capture attempt exposed the missing window; native regression verifies a fallback for a deselected profile |
| P2 | Test-host network logging could load/write the real app's diagnostic file | Test lifecycle keeps this logger in memory and never loads or saves the production file | Source guard in addition to isolated preferences |
| P2 | The CLI settings/sidebar stayed green after a historical sync even when the saved token had expired | Classify the saved token and expiry without reading live credentials; expired/incomplete is orange, unknown expiry is neutral, future expiry means local readiness only | 12 synthetic status tests, including expiry advancing without snapshot mutation |
| P2 | CLI sync accepted missing/expired tokens, ignored failed secure persistence, and saved success metadata separately | Validate token and expiry; commit credentials/metadata together; throw on failed save; refresh usage only after successful sync | Exact-body transaction regression failed in four methods before the fix; all 7 transaction tests pass afterward |
| P3 | Small labels, unlabeled icon/traffic-light controls, missing Reduce Motion support | Larger readings/copy, named controls, native button semantics and motion preference | Source and light/dark render inspection |
| P3 | Status-item cache could outlive removed buttons or ignore template/dimension changes | Clear lifecycle cache/timer; include image dimensions and template mode in its identity | Source inspection |
| P3 | Normal percentage/badge changes could cross the menu item's coarse width boundary | Reserve three digits and the saved-reading badge before needed | Width regression covers normal range; preserves existing fixed-length crash mitigation |

## Review coverage

| Area | Checked | Limits |
|---|---|---|
| Provider data | Claude selector/identity/rotation; Codex auth, response DTO, normalization, binding, retries and manual persistence | Synthetic credentials only; provider uptime/login approval is external |
| Storage | Existing recoverable immutable Keychain snapshots and visible persistence errors; activation preserves latest state | Unsigned Keychain round trips can skip; not a complete signed Keychain qualification |
| Network/privacy | Passive usage polling, official Codex HTTPS destinations and redirect refusal, token-free refresh diagnostics, local heartbeat | No intrusive production probes or reading of actual secrets |
| Updates/ownership | Pinned Sparkle dependency, owned feed and feedback destination; attribution retained | Personal Apple Development signing is not public notarization |
| Interface | Combined/individual popup, percentage mode, Fable at zero, unavailable windows, stale/error recovery, settings entry, labels/keyboard and detached sizing | Automated rendering is not a complete mouse/VoiceOver interaction audit |
| Reliability/performance | Real lifecycle spinners, guarded refresh entry, image deduplication/cache cleanup, fixed menu-item lengths, bounded scroll content | No claim of a prolonged real-machine heavy-load soak or zero possible crashes |
| Compatibility | Legacy Codable caches, per-profile state, full existing regression suite, arm64+x86_64 optimized build | Xcode 27 beta qualification differs from CI's unavailable Xcode 26.0.1 |

## Validation and visual evidence

Focused command set (synthetic, no real accounts):

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/test_profile_activation.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/test_claude_account_matching.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/test_claude_background_polling.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/test_codex_account_binding.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/test_codex_auth_ownership.sh
LOCAL_CI_PACKAGES_DIR=/private/tmp/claude-personal-ownership-packages scripts/test_local_ci.sh --developer-dir /Applications/Xcode-beta.app --allow-toolchain-mismatch
```

`UsageRenderingTests` renders the actual card/row/renderer implementations with
synthetic fresh Fable-zero, saved expired-session, disconnected long-name, and
partial Codex readings in light/dark appearances. The inspected first pass has
legible controls, correct absent metrics, visible zero Fable, neutral saved
readings, and wrapped recovery copy. Images are retained as XCTest attachments
and under `/private/tmp/claude-polish-audit/rendered/`.

The initial focused UI build exposed a read-only SwiftUI accessibility
environment used incorrectly in the test harness. That test-only assignment
was removed; all 12 focused state/presentation/render tests then passed.
These fixtures are not the user's live quota readings or screenshots of the
installed app.

The first actual installed-app capture was obtained by reopening
`/Applications/Claude Usage.app`, identifying its own popup window and capturing
that window only. This verified normal application reopen and exposed excessive
vertical density. `testTwoProviderOverviewFitsWithoutScrollingPrimaryQuotas`
failed before the correction, then passed in both appearances after compact
rows and collapsed details. All three rendering tests pass. The measured pair
includes Claude's zero Fable quota and a saved/error Codex reading with plan and
credit metadata; both primary sections now fit the 680-point popup. Additional
profiles, extra usage rows or expanded details remain scrollable. The initial
851-point and final 527-point measurements are synthetic renders, not live quota
data. Only the combined layout is condensed; individual dashboards retain their
full subtitle and plan/credit display. Screen-reader descriptions retain period,
reset and missing-reading context.

The unified-bar extension adds six presentation tests, two native lifecycle
tests and one actual-render test. All 12 focused model/lifecycle/render tests
pass. The first focused build caught an ambiguous numeric literal in a new test
fixture; explicitly using `Double.infinity` resolved that test-only compiler
error. Synthetic images cover fresh/saved/missing readings in both appearances.
Summary widths reserve the numeric value and clock so missing → 0% → 100% and
Used → Remaining changes do not recreate or resize the native item. Multiple
accounts from the same provider get ordinal labels and full tooltip names.
Provider polling and authentication endpoints are unchanged by this extension.

Final local qualification passed at `build/local-ci.SS3J7Y`: **339 tests,
337 passed, 0 failed, 2 skipped**. The two skipped unsigned Keychain round trips
are not counted as verified signed-app storage behavior. Debug and optimized
universal arm64/x86_64 Release builds passed. Xcode 27.0 beta (27A5228h) is
explicitly non-parity with CI's Xcode 26.0.1. Result bundle:
`build/local-ci.SS3J7Y/TestResults.xcresult`.

All five focused command checks also passed on the integrated source: activation
5 tests, Claude identity 8 tests, passive polling 5 controls, Codex binding and
invalid usage 21 tests, manual Codex ownership/persistence 10 tests. These overlap
the full suite where the tests are hosted; their counts must not be added to the
full-suite total as unique coverage.

Final personal delivery was signed and installed from application source commit
`2986c9c`. Strict nested signature verification passed for
`com.0xysh.ClaudeUsage`, team `K739254VXU`, with hardened runtime and both
arm64/x86_64 slices. The installed executable matches the packaged executable,
and its exact executable was observed running from `/Applications/Claude Usage.app`.
The archive SHA-256 is
`0c0a9e758ebd5ce6cd617f41fad2eab322693300f0a523303183ac777abd09c3`.
The local build receipt is retained under ignored `release/personal/`.

An actual capture of the installed app on 2026-10-07 confirms one horizontal
summary beside the separate TwinQuota item. Normal application reopen produced
the app's 386 × 706-point popup (window 3148); both provider cards, the mode
switch and recovery actions fit visibly. Screenshots are kept locally under
`/private/tmp/claude-polish-audit/installed-unified-*.png`, not committed.
The user's actual Codex weekly reading is saved 8%, marked with a clock; Claude
and Fable remain unavailable. These are honest current display states, not
evidence of a successful live connection. Synthetic Fable-zero rendering is
verified separately and never substitutes TwinQuota's data.

### CLI connection follow-up

The user's later organization-selection screenshot showed one Claude.ai session
with two organization entries. The CLI's official `claude auth status --text`
reported **Expired — log in again**; its organization metadata matched the
first personal organization. That check reads status metadata only and does not
prove which organization currently has a paid quota. The browser wizard was
still at organization selection; neither organization discovery nor a historical
CLI sync flag establishes a successful usage response.

The CLI status now uses a pure saved-snapshot classifier, reevaluated every
30 seconds while settings are visible. It does not access the system login,
Keychain or provider in the view body. Green means the saved token has a future
expiry, not that a live request succeeded. Expired/incomplete snapshots receive
an actionable warning; legacy snapshots without expiry remain neutral.

CLI sync rejects missing/blank tokens, malformed expiry and known expired tokens.
It checks secure persistence before reporting success, commits sync metadata in
the same transaction, and notifies usage refresh only afterward. It preserves
other profiles and accepts legacy tokens without expiry without classifying them
as verified. Authentication endpoints and credential-source precedence are
unchanged by this correction.

All **19** focused classifier/transaction tests pass at
`/private/tmp/claude-polish-audit/CLISyncGreen.xcresult`. Claude account matching
also passes its 8 synthetic tests, and passive polling passes its 5 controls.
The follow-up hosted full suite at `build/local-ci.6ylKKw/TestResults.xcresult`
reports **358 tests: 356 passed, 0 failed, 2 skipped**. The same two unsigned
Keychain limitations and Xcode 27 beta non-parity apply. Debug and optimized
universal arm64/x86_64 Release builds also pass. Installation was deferred
while the user's browser wizard was pending to preserve unsaved login state.
After the user saved the personal organization, their dashboard showed fresh
Claude usage and Fable. Their subsequent Codex Test Connection also produced a
fresh weekly reading. The corrected app from source commit `036f402` was then
signed, installed and opened using the authoritative personal delivery script.
The previous installation was preserved. Strict nested verification passed;
the universal installed and packaged executable hashes match:
`646ffb2e498df071c6dba05db375dd9290574c73f088072edc9feffd1e6b1d3a`.
The final archive SHA-256 is
`a00481f819f5f53b4b537cca508f4a4c0e66c9b1a3548605d32a1772a02ecdd8`.

Normal reopen of `/Applications/Claude Usage.app` produced its 386 × 706-point
dashboard (window 3223). The actual installed-window capture at
`/private/tmp/claude-polish-audit/installed-cli-status-popup.png` shows both
accounts **Fresh** after restart: Codex weekly 12%, Claude weekly 100%, Fable 0%
and Claude Extra Usage 75%. The current Codex response has no session quota, so
that row stays unavailable instead of inventing 0%. This verifies live usage
display and preserved connections for these two configured accounts, including
browser-backed Claude. It does not establish exhaustive signed-storage failure
handling or long-duration heavy-load stability.

## Remaining live gates

These two accounts now display fresh readings in the installed app. The
browser-backed Claude connection works independently of the previously expired
CLI login. Using the CLI route requires signing in again and explicitly syncing
its credentials. Other older file-backed Codex profiles require their own
active-profile Test Connection to establish identity. The app now
provides direct recovery routes; it never guesses a login or shows missing usage
as a full/empty allowance. Actual Fable availability is decided by the provider
response, not the reference screenshot. Browser login succeeded for the user's
personal organization; this does not prove acceptance for every login method.
VoiceOver traversal, detached-window interaction, long heavy-load stability and
public release/notarization remain unqualified by these checks.

## Motion, brand and inline-credit follow-up

The subsequent scoped design request keeps the same provider-reading methods.
Its plan, original artwork provenance, color roles, native motion evidence and
local qualification are in [USAGE-DESIGN-AND-MOTION.md](USAGE-DESIGN-AND-MOTION.md).
Codex credits are now immediately visible and a missing Codex session is omitted;
the earlier collapsed-account-metadata layout finding is superseded by this
validated inline summary. Quota health colors remain distinct from provider
identity. The new final local gate passes 376 of 378 tests, with only the same
two unsigned Keychain skips, and optimized universal Release passes.

The motion/branding app from `8b8c087` was subsequently signed, installed
and observed running. Its installed executable matches the packaged bytes.
The actual visible usage popup confirms both accounts Fresh, Codex's inline
credit and omitted absent session, original logos, 7pt tracks and all Claude
quotas/controls together. Artifact details are in the design follow-up document
and ignored personal build receipt.

## Real counting and plain quota titles

The user's follow-up exposed that the first numeric transition moved endpoint
glyphs rather than counting intermediate values. The corrected scalar SwiftUI
Animatable counter visibly counts 20 → 44 → 65 → 80 in a native window,
synchronized with the fill, with exact sharp endpoints and static zero/unknown
readings. Weekly capsule tags are replaced by localized regular titles:
5-hour limit, Weekly, Weekly - all models and Weekly - Fable. All 14 existing
languages retain their existing entries; new model-specific weekly titles follow
the same convention. The final exact-state suite at
`build/local-ci.3icmGJ/TestResults.xcresult` passes 379 of 381 tests,
with 0 failures and the same two unsigned Keychain skips. Debug and optimized
universal Release pass on Xcode 27 beta `27A5228h`; this remains non-parity with
the unavailable Xcode 26.0.1 Actions toolchain. No new Actions run was started.

The final counting/title app from source
`97cf6fd58c6557ea3f9504a6467ab2ebdf5e5132` was personally signed, installed and
observed running. Elevated packaging passed strict nested signature verification;
the installed/package executable SHA-256 matches:
`e060734b7980600f5928a1c058163cb214432465a7327c2b29641ae627b9ec36`.
ZIP SHA-256: `96e7ce2733614f8b634f91d32389a173728f8be0791f21550f27564ea469fa6c`.
The delivery log is `/private/tmp/claude-polish-audit/install-counting-labels-final.log`.
Fresh elevated strict verification of the exact installed app and nested Sparkle
components also passes in `/private/tmp/claude-polish-audit/current-installed-signature.log`.

An opening capture of the actual installed popup (PID 86045, own window 3350)
now confirms the counter/fill integration: Codex/Claude weekly/Extra Usage move
through **3/30/22%**, then **8/65/49%**, to sharp **13/100/75%** endpoints.
Measured session and Fable zero remain sharp, and both cards fit. The earlier
endpoint-only captures came from reopening an already visible popup; reopening
intentionally leaves it visible, so restart/open capture was required.
Evidence is `/private/tmp/claude-polish-audit/installed-counting-reopen/`;
its timings record capture starts, not precise rendered-frame timestamps.
Own-window capture has gray vibrancy fallback; the actual dark appearance is
recorded separately in `installed-counting-labels-final.png`.
Native evidence, current artifact details and remaining Reduce Motion/cancellation
verification limits are in USAGE-DESIGN-AND-MOTION.md and the ignored personal
build receipt. Personal signing does not constitute public notarization.
