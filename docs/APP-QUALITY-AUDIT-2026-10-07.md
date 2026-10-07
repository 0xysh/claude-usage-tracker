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

## Remaining live gates

Claude requires a valid signed-in Claude Code account and an explicit sync when
its credentials are missing/expired. Older file-backed Codex profiles require
their own active-profile Test Connection to establish identity. The app now
provides direct recovery routes; it never guesses a login or shows missing usage
as a full/empty allowance. Actual Fable availability is decided by the provider
response, not the reference screenshot. Embedded-browser login acceptance,
VoiceOver traversal, detached-window interaction, long heavy-load stability and
public release/notarization must not be represented as verified by synthetic
tests alone.
