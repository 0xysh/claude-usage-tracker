# Local performance comparison — 2026-10-07

The sufficient outcome was to determine whether lower-memory presentation work
provides a useful improvement while preserving reliable menu readings and fast
access to both accounts. The experiment did **not demonstrate a meaningful
resource improvement in the measured states**. The candidate was rolled back;
the previously qualified signed app remains installed and running. This report
is the only tracked delivery change.

## Variants and method

A is source `7aa7802d32716b2bead5ff5733ce6b20279c36a4`, the existing signed personal
app. B contains two candidates: lazy construction/release of the popup's hosting
controller, and an early one-image visual cache that skips identical combined
menu artwork while updating its tooltip and accessibility metadata. Provider
requests, authentication, polling cadence and stored readings were unchanged.

The suggested diagnostic-log optimization was excluded: the persisted
`network_logs.json` file was absent, so there was no saved history to avoid loading.
Only its existence was checked; no log contents or credentials were collected.

Run order was A1 → B1 → A2, each with a fresh process from the exact installed
bundle. The second A run brackets ordinary run-to-run variation. Sampling used
`proc_pid_rusage(RUSAGE_INFO_V4)` once per second. Each run spent at least 60 seconds
with no own popup visible, followed by a normal application reopen. Summary
windows are seconds 10–60 after process collection starts and seconds 5–40 after
the open request. Both are deliberately past startup/entrance motion.
No builds/tests ran during these measurement windows. Other user applications
continued running; this is a bounded real-machine observation, not a controlled
laboratory or long-term battery/leak test. Current host: macOS 27.2 (26B5091g).

Physical footprint and resident memory are separate accounting views, not
interchangeable estimates of exclusive allocations. CPU is the interval delta
of cumulative user+system time, as a percentage of **one core**. The collector
converts Mach time units through this machine's timebase (125/3 nanoseconds per
tick). A1's originally labelled raw fields were corrected from preserved raw
Mach counters before comparison; no CPU results use unconverted ticks.
See Apple's [rusage implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c)
and [task time accounting](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c).

## Measured results

Memory values are median MiB (1,048,576 bytes); CPU is the interval mean.

| Variant | State | Physical footprint | Resident memory | CPU, one core |
|---|---|---:|---:|---:|
| A1 | idle | 23.03 | 89.92 | 0.168% |
| A1 | open | 39.31 | 102.94 | 2.386% |
| B1 | idle | 23.38 | 89.22 | 0.289% |
| B1 | open | 40.70 | 98.69 | 1.706% |
| A2 | idle | 22.94 | 82.67 | 0.184% |
| A2 | open | 40.02 | 103.12 | 1.777% |

A1/A2 idle resident memory itself varied by more than 7 MiB, while physical
footprint stayed near 23 MiB. B's idle footprint was slightly higher. Its open
footprint also did not improve. Open CPU in B was close to the second A run;
the first A run was higher. These observations do not establish a CPU/energy
saving. Fewer synthetic renders alone is insufficient reason to ship extra
presentation lifecycle/cache complexity.

## Opening speed and data correctness

Observed request-to-visible-window upper bounds were A1 **391 ms**, B1 **469 ms**,
and A2 **499 ms**. These include LaunchServices and external window-observer
latency (roughly 120–140 ms between observer checks in B1/A2). They are **not
precise internal render timings**, and the 77 ms A1/B1 difference cannot establish
a slowdown at this resolution. The popup was accessible promptly in all runs;
its intentional 600 ms number/bar entrance is separate from window availability.

B's actual installed popup capture showed both accounts with Fresh data, Fable,
weekly-only Codex and inline credits. Synthetic tests exercised percentage and
health changes, missing versus measured zero, staleness, errors, display mode,
theme, ordered account layout and accessible help. Deferred close-release tests
covered identity/visibility races and independent detached-panel ownership.
A focused independent source review found no blocker.

The computer-use tool could not access the menu app reliably; attempts to dismiss
it via outside clicks/the existing shortcut did not produce a verified close.
Therefore **post-dismissal memory, repeated actual native close/reopen and native
detachment were not measured**. Synthetic lifecycle coverage does not prove
those runtime resource outcomes. The result rejects shipping this candidate on
current evidence; it does not prove that releasing hidden views can never help.

## Qualification and retained evidence

- B: `build/local-ci.6NX99y/TestResults.xcresult`, 397 total / 395 passed / 0 failed /
  2 unsigned Keychain skips; Debug and optimized universal Release passed.
- One earlier experiment test asserted immediate global NSImage destruction
  and failed despite cleared ownership. It was replaced with observable cache
  eviction/button-reference checks, then the full gate was rerun successfully.
- Xcode 27 beta 27A5228h was used; qualification is non-parity with unavailable
  workflow Xcode 26.0.1. No GitHub Actions run was requested.
- A executable SHA-256: `da45148c03f9b05b3424f483bd64cc9e3dba44fcf26d1160ca14693e579f9896`.
- B executable SHA-256: `0493317722d9894dca9905bd0c32e484877f26d5ea0934aa17d98a48d6f3749f`.
- Numeric samples, phase metadata, normalized results, exact signed bundles and
  candidate diff/tests: ignored `build/performance-experiment/`.
- B installed-popup capture: `/private/tmp/claude-polish-audit/performance-B1-popup.png`.
- Final installed A popup capture: `/private/tmp/claude-polish-audit/performance-final-A-popup.png`.
- Installation log: `/private/tmp/claude-polish-audit/install-performance.log`.
- Final A-source hosted test result: `build/performance-experiment/BaselineFinalTests.xcresult`
  381 total / 379 passed / 0 failed / 2 unsigned Keychain skips on the restored A source.
  The final installed/package binary hash and strict signature were reverified;
  the original optimized universal Release artifact is unchanged.

Stop condition: retain the existing reading method, interface and signed app;
record the actual measured benefit and limitations. No widgets, provider rewrite,
new diagnostic store or speculative memory-saving feature is included.
