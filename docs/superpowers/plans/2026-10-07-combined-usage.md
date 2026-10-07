# Combined Usage Implementation Plan

> **For agentic workers:** Execute the approved plan in this chat. Use focused subagents for independent parser and credential work, with one final independent review.

**Goal:** Show Claude and Codex together, show reported Fable at 0%, and distinguish missing or outdated readings from live usage.

**Architecture:** Reuse the existing profile selection, refresh services and usage rows. Add an app-wide combined-popover preference and provider-labelled cards with per-profile freshness/errors. Preserve the existing separate menu-bar icons and offer the existing single-profile popup as a setting.

**Tech Stack:** SwiftUI, AppKit, Foundation, XCTest, existing Xcode build/package scripts.

## Global Constraints

- TwinQuota is visual inspiration only; preserve our existing polling endpoints and counter-reading method.
- Never print, save, screenshot or commit real credentials; diagnostics expose only metadata.
- Do not refresh or modify shared Codex auth.json.
- Use local tests, with explicit non-parity toolchain disclosure. Do not start GitHub Actions.
- Preserve account configuration and previous app builds during installation.

## Task 1: Reported Fable availability

Files: ClaudeUsage.swift, ClaudeAPIService.swift, FableUsageTests.swift.

Interface: `ClaudeUsage.hasFableUsage: Bool`, backed by an optional persisted availability flag. The API parser supplies true only for valid reported utilization, including zero, in legacy or scoped Fable/Mythos responses. Nil preserves legacy inference.

- [x] Add synthetic legacy/scoped zero, missing/null/invalid, reset-date and persistence tests.
- [x] Observe the zero-availability test failing against the existing parser.
- [x] Implement availability without changing polling or authentication.
- [x] Run focused synthetic tests; include them in the final hosted suite.

## Task 2: Combined provider cards

Files: PopoverContentView.swift, new CombinedUsageView.swift and UsageDataState.swift, PopoverSettingsView.swift, SharedDataStore.swift, MenuBarManager.swift, UsageDataStateTests.swift.

Interface: preference `popoverShowAllProfiles`; `UsageDataState.resolve(lastUpdated:refreshFailed:now:)`; `MenuBarManager.profileRefreshErrors: [UUID: String]`. Cards consume the selected profile's own usage and console data, never active-profile placeholders.

- [x] Test missing data, fresh/stale boundaries, and failed-refresh state with synthetic dates.
- [x] Add combined-card layout, provider accents, profile name, freshness, existing usage rows and a bounded scroll area. Gate Fable rows on `hasFableUsage`.
- [x] Add a persistent Used % / Remaining % switch in the combined popup, reusing the existing multi-profile display preference; select Used % for this user.
- [x] Present missing data as unavailable, cached/error readings as last known, and provide refresh/settings actions.
- [x] Refresh all selected profiles when the combined popup is enabled; track errors separately. Fix the single-profile title/data mismatch and prevent .empty from appearing as a real reading.

## Task 3: File-backed accounts and qualification

Files: CodexUsageProvider.swift, CodexAccountView.swift, Profile.swift, synthetic binding tests; any verified CLI sync defect only after diagnosis.

Interface: nonsecret `Profile.codexAccountID: String?`; bind only after successful active-profile file-backed fetch. Permit inactive reads only for matching identity; reject mismatch or unbound profiles. Keep manual-profile auth behavior.

- [x] Demonstrate the active/inactive file-access defect and test account isolation, mismatches and manual profiles.
- [x] Inspect minimal safe Claude metadata to distinguish expired/missing credentials from an app bug. Do not invent a working connection.
- [x] Run one focused independent review, full isolated local hosted suite and optimized universal Release build.
- [x] Commit with `[skip ci]`, update the existing draft PR, build/sign/install through script/build_and_run.sh, and enable the combined view for this user.
- [x] Verify installed identity, launch and actual combined UI. Verify live readings or report the exact remaining login requirement.

Stop when the exact installed app passes the relevant checks and the combined UI is inspected. Additional browser-login repair is outside this delivery unless it blocks the approved CLI connection.

## Delivery evidence (2026-10-07)

- Final local gate: `build/local-ci.IMtqVO`, Xcode 27.0 (27A5228h), explicitly non-parity with CI Xcode 26.0.1. Debug and optimized arm64/x86_64 Release passed. Hosted suite: 297 passed, 0 failed, 2 unsigned Keychain round trips skipped.
- Focused independent review closed the browser organization isolation defect and found no remaining required blocker.
- Signed app installed and exact executable observed running at `/Applications/Claude Usage.app`; previous installation and archive preserved in `release/personal/backups/`. Combined view and Used percentage mode enabled.
- Normal signed-app diagnostics report a saved Claude CLI configuration without a valid access token; reconnect/sync is required. The older inactive Codex profile needs its first active connection check before background file reads are allowed. No real credential values were read or displayed during this verification.
- The user confirmed that both accounts and the Used % / Remaining % switch appear in the opened popup. Automated AX/screenshot access to this menu-bar app continued timing out; the UI evidence is user confirmation, not an automated visual inspection. Read-only `claude auth status --json` returned loggedIn=false, authMethod=none, exit 1. Claude CLI login and sync plus the first active Codex connection check remain live setup steps; additional browser login repair is outside this delivery.
