# Verification

## 0.2.0 release preparation — 2026-09-21

Verified locally with Xcode 27.0 (27A266a), Swift 6 language mode, and an iPhone 18 Pro /
iOS 27.0 simulator. The deployment target remains iOS 16.

| Check | Result |
| --- | --- |
| Package build and full Swift Testing/UIKit regression | 89 tests in 10 suites passed |
| Section update and captured-layout integration | Passed with both supplied data sources |
| Standalone IM and Store examples importing public API | Built successfully |
| Example UIKit counts, cell types and shared installation action | All 10 smoke checks passed |
| Local documentation links and heading anchors | All 14 resolved |

The full test run took 14.651 seconds. Its result bundle is
`/private/tmp/parade-0.2.0-release-20260921.xcresult` (89 tests, zero failures).
The standalone examples were rebuilt and all smoke checks rerun against the same
implementation, including the final membership-validation fixes.
The example report is written to the simulator application's
`Documents/smoke.json`. Xcode emitted an App Intents metadata extraction warning;
the standalone example build emitted a linker sysroot warning.

New coverage includes layout-only changes without cell reconfiguration, captured
layout inputs, independent queued section updates, reorder preserving accepted
content, stale-instance rejection after same-ID replacement, execution-time global
ID conflicts followed by successful updates, atomic cell transfers, attachment
reservation during suspended application, queued removal followed by reattachment
of the same instance, and structural-stage layout identity.
The previous Flow delegate forwarding test was removed with that unsupported API.
Reattachment preserves the submitted content and layout even when live section state
changes before execution. Reordering preserves a surviving section's accepted
presentation even if its unsubmitted live content is invalid.
Initial attachment is covered both while executing and while still queued: a later
reorder ignores unused invalid live content and preserves accepted layout on both
data sources. Content rejection is checked in FIFO order, with diagnostics and
subsequent valid operations preserved.

These results validate this local implementation. They do not establish iOS 16
runtime behavior, a CI result, device performance, or animation quality. The limits
and reproduction instructions below continue to apply.

## Published 0.1.0 verification

The following historical results describe the published 0.1.0 implementation.

### Local release verification

Verified on 2026-09-17 with Xcode 27.0 (27A266a), Swift 6 language mode,
and an iPhone 18 Pro / iOS 27.0 simulator:

| Check | Result |
| --- | --- |
| Generic iOS Simulator build, deployment target iOS 16 | Passed |
| Swift Testing and UIKit integration | 80 tests in nine suites passed |
| Independent structural replay | 23,386 default-algorithm and 2,000 alternate-algorithm transitions passed |
| Standalone examples importing only public API | Built successfully |
| IM and App Store UI smoke checks | All 10 passed |

The final test run took 6.539 seconds. There were no Swift warnings, UIKit assertions,
or test-runner crashes. Xcode emitted an App Intents metadata extraction warning;
the standalone example build emitted a linker sysroot warning. Neither prevented
compilation or execution.

## Coverage

- **Input and identity:** duplicate section/cell IDs, supplementary identity scopes,
  invalid addresses, both conflict coordinates, first-error precedence, captured
  compositions, and valid → invalid → valid submissions without losing the baseline.
- **Diff and planning:** alternate algorithms through public API, optional identities,
  section reordering, cross-section transfers through inserted/deleted sections,
  source content during structural moves, final target-coordinate content edits,
  malformed changes, incomplete moves, and invalid/conflicting batches. The replay
  oracle reconstructs results from operations and source identities independently
  of production planning and validation.
- **UIKit updates:** heterogeneous cells, retained empty sections, self-sizing,
  content-only and behavior-only changes, same-ID view-type replacement, dynamic
  supplementary topology/content, explicit reloads, off-window updates, and recovery
  before an invalid plan reaches UIKit.
- **Queue and completion:** FIFO and reentrant submissions, diagnostic callbacks,
  current-data queries during suspended updates, and public completion only after
  UIKit and behavior refresh settle.
- **View lifecycle:** generic presenter erasure, optional capabilities, concrete-view
  dispatch, equal-content policy/action changes, explicit cleanup of shared bindings,
  prepared views redisplaying without a new dequeue, and final callbacks after removal.
- **Data-source injection:** an independent implementation using only `import Parade`,
  factory invocation once, instance retention/release, native/default semantic parity,
  non-Sendable reference identities, removal/reinsertion, and missing-position queries.
- **Examples:** IM uses the default data source; App Store injects the Apple adapter.
  Checks inspect actual UIKit counts and cell types and send an install button action,
  verifying that all three occurrences of the app change to `Open`.

## Reproduction and CI

Use the build/test commands in the [root README](../README.md#development), choosing
an available iOS simulator. Follow the [example instructions](../Examples/README.md)
to build and run the public-API app and inspect its `Documents/smoke.json` report.
Pass `-resultBundlePath <path>.xcresult` to `xcodebuild test` to save a result bundle.

The [CI workflow](../.github/workflows/ci.yml) builds with Xcode 16.0, then runs the
full test suite on Xcode 16.4 / iOS 18.5 and builds the public-API example app.
The minimum-toolchain check uses SwiftPM with Xcode 16.0's device SDK and an
`arm64-apple-ios16.0` target, without requiring a simulator runtime. The UIKit test
step selects Xcode 16.4 explicitly and uses the runner's preinstalled iOS 18.5 runtime.
It runs on main-branch pushes, pull requests, and manual dispatch, and retains test
result bundles for seven days. Example UI smoke checks are performed locally;
CI compiles the examples without launching them. Consult the
[run for the release commit](https://github.com/Weixi779/Parade/actions/workflows/ci.yml)
for its result; the local results above do not stand in for a CI run.

## Limits

The declared deployment target is iOS 16, but iOS 16 runtime execution has not been
verified. The locally installed iOS 16 runtime is unsupported by this host's macOS.
Building with a newer SDK and an iOS 16 target does not prove iOS 16 execution.

Both supplied data sources execute on MainActor. These checks establish functional
behavior for the covered scenarios, not background scheduling or a performance
advantage over other frameworks. Real-device performance and animation quality
remain unverified. Simulator is not an accurate performance proxy for processing/CPU,
graphics/Metal, memory, networking throughput/latency, Metal GPU behavior, frame timing,
memory pressure/Jetsam, or thermal behavior.

The examples use local state and simulated content. Real media/network requests,
keyboard interaction, and application navigation are outside their verification scope.
