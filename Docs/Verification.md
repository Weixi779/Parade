# Verification

This report describes the 0.1.0 implementation. Earlier refactoring runs are
preserved in Git history; the counts below refer to the final implementation.

## Local release verification

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
