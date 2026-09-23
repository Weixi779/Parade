# Verification

## 0.3.0 release review — 2026-09-23

Reviewed the complete change from 0.2.0: public API renaming, section reconciliation,
attachment/visibility ownership, queued updates, callback ordering and reentrancy,
same-ID replacement, stale view callbacks, and instance/resource release.
The data-source and diff changes are naming changes; their update behavior is preserved.

| Check | Result |
| --- | --- |
| Full package and UIKit regression, Xcode 27.0 / iOS 27.0 | 126 tests in 12 suites passed |
| Default and diffable source integration | Passed |
| Standalone examples compiled against the public API | Passed, targeting iOS 16 Simulator |
| IM and Store example smoke checks | All 10 passed |

The full run took 14.838 seconds. Its result bundle is
`/private/tmp/parade-0.3.0-review-20260923.xcresult`. The example report is
`Documents/smoke.json` in the simulator application's data container. The existing
standalone-build linker sysroot warning remains; the build and runtime checks passed.

Lifecycle tests cover independent attachment and collection visibility, offscreen
sections, first/last displayed views, supplementary-only sections, cross-section
cell transfers, same-ID replacement with a retained cell, delayed end callbacks,
visibility changes during suspended updates, callback reentrancy, and owner teardown.
The store-specific tests and their failure/retry boundaries are described below.
These local checks do not establish older-toolchain compatibility, iOS 16 runtime
behavior, real-device performance, or animated visual quality; CI separately checks
the minimum compiler and its configured simulator runtime.

## Content and snapshot naming — 2026-09-23

Renamed the output contract to `SectionContent` / `DefaultSectionContent` and
`SectionPresenter.captureContent()`, with associated type `Content`. Captured section
and collection versions are now `SectionSnapshot` and `CollectionSnapshot`.
Public access levels, data-source injection, and runtime behavior remain unchanged.
The migration mapping is in [the changelog](../CHANGELOG.md#api-naming-changes).

The complete suite passed **126 tests in 12 suites** in 14.777 seconds on
Xcode 27.0 / iOS 27.0. The result bundle is
`/private/tmp/ParadeNaming-20260923.xcresult`. These checks cover the renamed public
API and existing behavior. The standalone examples also compiled successfully using
only `import Parade`, targeting iOS 16 Simulator; the example build emitted its
existing linker sysroot warning. Local documentation links resolve. These checks
do not establish older-runtime or device behavior.

## SectionStore integration — 2026-09-23

Added 23 public-API tests (35 cases after parameter expansion): 17 reconciliation
tests and six UIKit integration tests exercised with both supplied data sources.
They verify identity/state preservation, heterogeneous types, replacement and
reinsertion, ordered changes, duplicate rejection before side effects, input/closure
and presenter lifetimes, suspended acceptance, failure/cancellation and retry.
Integration checks inspect actual cells and layouts, attachment changes, rejected
structure/content preserving the displayed baseline, and atomic retained-cell transfers.
Async acceptance uses an explicit continuation gate rather than timing sleeps.

The final combined working-tree suite passed **126 tests in 12 suites** in 14.663
seconds on Xcode 27.0 / iOS 27.0 (iPhone 18 Pro). The result bundle is
`/private/tmp/ParadeSectionStore-20260923-final.xcresult`. Source and test hashes
were unchanged during this run. An iOS device build targeting `arm64-apple-ios16.0`
also passed with the installed Xcode 27 toolchain; this does not verify Xcode 16
compiler compatibility or iOS 16 runtime behavior.

Coverage records all 60 executable lines of `SectionStore` and 34/36 lines of
`SectionDefinition`. The two unexecuted closures produce messages for failing ID
preconditions; intentional process-termination tests are not included. Line coverage
is supporting evidence, not a substitute for the behavioral assertions above.

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
