# Usage presentation design and motion

## Delivery plan

Refine the existing native menu-bar overview, preserving its provider-reading,
authentication and storage methods. Required behavior:

1. Show only Codex windows actually reported. Missing session is omitted;
   a measured zero remains visible. Weekly data never derives from a plan name.
2. Display Codex plan and credits immediately, without disclosure. Keep recovery
   help collapsible. Credits retain their provider unit; no USD conversion.
3. Use one identity palette across provider headings, rails, controls and the
   combined menu bar. Claude is warm orange, Codex is blue. Green/amber/red still
   communicate quota health; saved data remains neutral and visibly dated.
4. Replace generic provider symbols with original vendor artwork. Preserve logo
   colors/proportions; the blue UI accent does not recolor OpenAI's mark.
5. Increase quota tracks from 4 to 7 points. Replay one shared 600ms ease-out fill
   on each popup opening. Actual reading changes settle in 280ms. Native rolling
   digits get a restrained, finite blur pulse (maximum 1.1pt); zero/unknown values
   stay sharp. Hover and disclosure feedback remain brief and scoped.
6. Respect macOS Reduce Motion: immediate correct values, no sweep/roll/blur.
   VoiceOver always receives the measured target, never decorative entrance zero.

Acceptance gates: synthetic light/dark renders including weekly-only Codex,
inline zero/finite/unlimited credit, missing-versus-zero session and quota overflow;
finite/clamped animation geometry and accessible identity contrast; native motion
replay/static preview; full isolated local tests plus optimized universal Release;
signed personal installation and capture of the installed usage popup. No cloud
CI run. Stop when these gates pass; no unrelated UI/backend rewrite.

## Reference and rationale

TwinQuota's local `Views/Theme.swift`, `Views/Components.swift`,
`Views/DropdownView.swift` and `Views/ProviderQuotaCard.swift` use a 7pt capsule
and shared `openBeat` reset/fill over 600ms. Its number labels are static. Only
that presentation behavior informs this change; its reading method is not used.
Our popup publishes its own presentation UUID rather than listening globally to
another application's popover notifications. Native AppKit popover animation stays
disabled because of the previously verified macOS resize-recursion defect.

Rolling digits use Apple's [numericText(value:)](https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(value:))
and finite SwiftUI keyframes. No permanent animation timer or new dependency.

| Role | Light | Dark |
|---|---|---|
| Claude UI identity | `#A4492E` | `#F3AD8D` |
| Codex UI identity | `#1F5BC8` | `#91B8FF` |
| Provider artwork | Original vendor asset | Original vendor asset |
| Quota health | Existing green/amber/red semantics | Existing green/amber/red semantics |
| Saved/unavailable | Neutral text, explicit state/date | Neutral text, explicit state/date |

Identity text is tested at >=4.5:1 against white and representative dark card
`#1D2029`. Accent rails and understated surface tints reinforce identity without
turning whole cards into saturated blocks. The [OpenAI brand guidelines](https://openai.com/brand/)
require the original monochrome artwork; blue is our adjacent interface accent.

## Artwork provenance

Claude Spark Clay is copied byte-for-byte from the [official press kit](https://anthropic.com/press-kit),
observed redirect `https://www-cdn.anthropic.com/ae59ca4ca194dac9c9dc3bc78c5829468cb0e8af.zip`.
SVG SHA-256: `6d53db4be375e899c937c26cf16684a80d6e869b1928d72b37748bef2560e219`.
Original fill `#D97757`; the vector is scaled proportionally and not recolored.
Vendor marks belong to their respective owners and identify the connected
services; they are not this app's primary identity or an endorsement claim.

OpenAI's original 21×21 black/white Blossom assets are copied byte-for-byte from
[OpenAI's sign-in devkit](https://github.com/openai/sign-in-with-chatgpt-devkit/tree/f723814abdccec135b519c451fb6e1992ee5e933/assets/brand).
Black SHA-256: `b8b9aba7ba591f54bf1805f422bc23f32c44ee993643cc378cc77f766061f7a1`.
White SHA-256: `568ce2e8701934856aaafc0ed1c3d0300f6c2ff384d0ae743dd1dea08570e12c`.
Both use their original color; the asset catalog selects white in dark appearance.
No asset is synthesized or recolored.

## Validation

- Focused native UI suite: **24 passed, 0 failed, 0 skipped**, including actual
  light/dark rendering, weekly-only Codex, measured zero versus absent session,
  zero/finite/unlimited/invalid credits, original artwork and overview height.
  Result: `/private/tmp/claude-polish-audit/MotionBrandingFocusedFinal.xcresult`.
- First focused pass exposed a 10pt overview overflow after adding inline credit.
  Tighter card spacing/padding fixed the cause while retaining text/bar sizes;
  the unchanged two-window overview gate then passed. The weekly-only/full-Claude
  fixture also fits, including Fable and Extra Usage.
- Full isolated local gate: **378 tests, 376 passed, 0 failed, 2 unsigned Keychain
  skips**; Debug and optimized arm64/x86_64 Release passed. Exact result:
  `build/local-ci.4pu4cd/TestResults.xcresult`. Xcode 27 beta (27A5228h), explicitly
  non-parity with Actions' unavailable Xcode 26.0.1. No Actions run was requested.
- One bounded independent source review found no task-scoped blockers in motion
  replay/cancellation, Reduce Motion, quota availability, credits, assets or
  identity/semantic-color separation. Provider/auth/read paths are unchanged.
- A finite isolated native preview compiled the actual motion file (SHA-256
  `a12ab17fc8f88817536558455c2a17ad60bd71e52d2d2c3b33d7e297092e5436`)
  and actual central formatter. Own-window captures visibly show empty → partial
  fill/blur → sharp 80%, plus UUID replay. Measured zero and absent values stay
  sharp. The preview exited itself after about 11 seconds, without accounts or
  requests. Evidence: `/private/tmp/usage-motion-native-evidence/verification-receipt.json`.
- Timing coalesced synthetic update/suppression events: the preview establishes
  their correct sharp final targets, but did not capture the 280ms data-update
  pulse or prove cancellation midway. Geometry/static policy tests and source
  review cover those paths; system Reduce Motion was not changed for testing.

Signed installation and actual live popup verification are recorded below once
packaging completes.
