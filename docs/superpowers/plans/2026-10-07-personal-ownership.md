# Personal Fork Ownership Implementation Plan

> For agentic workers: execute the bounded tasks below; use the existing root/subagent file assignments and one focused final review.

**Goal:** Keep the application's monitoring features while returning feedback, daily activity records, and update ownership to the user's fork.

**Architecture:** Reuse the existing service/UI boundaries. The daily heartbeat becomes a local latest-record store, feedback opens a user-published GitHub issue draft, and Sparkle uses this fork's feed and signing key. Provider authentication stays with Anthropic/OpenAI; author attribution stays accurate.

**Tech Stack:** Swift/SwiftUI, Foundation, XCTest, Sparkle, GitHub Actions/Pages.

## Global Constraints

- Repository: `0xysh/claude-usage-tracker`.
- Do not launch the application or read live account credentials during validation.
- Do not publish feedback automatically or include name/email/account credentials in its draft.
- No silent fallback to the upstream update feed or signing key.
- Store private update-signing material outside Git with owner-only permissions; only its public key belongs in Info.plist.
- Preserve monitoring logic, profiles, history, and notification behavior. This task does not change the separate Keychain/shell/inference findings in the audit.

## Task 1: Local daily records and project links

Files: `HeartbeatService.swift`, `AppDelegate.swift`, `Constants.swift`, `GitHubService.swift`, `AboutView.swift`, `SupportView.swift`, `HeartbeatServiceTests.swift`.

- [x] Add isolated UserDefaults tests for version/date recording, the 24-hour threshold, and migration from the old remote-ping timestamp.
- [x] Confirm the original service cannot satisfy the new local-record interface.
- [x] Implement `HeartbeatService(defaults:)` and `recordIfNeeded(now:version:)`, retaining the timer cadence and removing HTTP requests.
- [x] Route repository navigation and contributor lookups through `Constants.GitHub` for the fork.
- [x] Run the isolated XCTest bundle against exact source files.

## Task 2: Feedback drafts and local mobile interest

Files: `FeedbackPromptView.swift`, `MobileAppView.swift`, `FeedbackIssueURL.swift`, `FeedbackIssueURLTests.swift`, localization strings.

- [x] Add tests for the configured GitHub destination, Unicode/query escaping, absence of personal metadata, empty messages, and invalid repository URLs.
- [x] Confirm the helper is initially absent.
- [x] Implement `FeedbackIssueURL.makeURL(repositoryURL:role:message:) -> URL?` using URLComponents.
- [x] Open a draft only, report opening errors accurately, and retain the entered message for revision.
- [x] Keep mobile interest local and make the interface describe a saved preference without promising a notification service.
- [x] Enable Issues on the fork as the user selected GitHub feedback; do not create an issue.
- [x] Run isolated URL tests.

## Task 3: Fork-owned update configuration

Files: `Info.plist`, `Package.resolved`, `project.pbxproj`, `.github/workflows/generate-appcast.yml`, `.github/workflows/update-homebrew-cask.yml`, `.gitignore`, `docs/PERSONAL_UPDATES.md`.

- [x] Pin official Sparkle 2.10.0 and verify the downloaded tool archive checksum in the workflow.
- [x] Create an owner-only local private signing seed without printing it; embed only the matching public key.
- [x] Route appcast/archive URLs to the fork and make workflow URLs derive from its repository context.
- [x] Bootstrap gh-pages safely and deploy using the supported Pages artifact workflow, with scoped built-in GitHub token permissions.
- [x] Keep Homebrew publishing available only for an explicitly configured fork-owned tap.
- [x] Document first-release requirements: secure private signing key, Apple signing/notarization credentials, Pages configuration, and a signed personal release. Do not claim live updates work before those are met.

## Final gates and stop condition

- Isolated XCTest bundle passes without launching the app.
- Debug and Release compilation pass on the exact source; no app launch, install, or account connection.
- Localizations and plist/workflow structure validate; diff is scoped and private material is ignored.
- One focused review checks destination ownership, publication semantics, and update prerequisites.
- Hand off the source changes and exact remaining distribution prerequisites. Do not broaden this task into the separately reported security fixes or a live release.

## Final validation evidence

- 2026-10-07: `scripts/test_personal_ownership.sh` passed all 11 tests in an unhosted XCTest bundle.
- Debug and Release compilation passed using Xcode 27.0 beta; neither build was launched or installed.
- All 14 localization files, plist settings, both publishing workflows, their 13 shell blocks, and embedded Python parsed successfully. `git diff --check` passed.
- One independent review identified and resolved the oversized feedback URL, remaining question link, and misleading mobile-interest subtitle.
- The private signing seed remains ignored and owner-only. Issues is enabled on the fork; Pages, release credentials, secret upload, and a signed personal release remain prerequisites.
- Existing build warnings about Info.plist in Copy Bundle Resources and skipped App Intents metadata remain outside this ownership task.
