# Verification

## 1.0.0 minimum-toolchain correction — 2026-10-03

The first publication CI run on `8ea19101` failed in Xcode 16.0 / Swift 6.0 before
tests started. The compiler crashed in `AllocStackHoisting` while compiling
`validateMembership(_:)`, whose typed error was nested in `CollectionSnapshot<Layout>`.
The [failed run](https://github.com/Weixi779/Parade/actions/runs/37105694303) preserves
the compiler trace.

The correction makes that layout-independent error a non-generic internal
`CollectionValidationFailure`. Public API, validation order, error payloads and
diagnostic locations are unchanged. The complete local suite passed again:
**150 tests in 13 suites**, 6.760 seconds, with result bundle
`/private/tmp/ParadeRelease-1.0.0-compat.xcresult`.

The initial candidate results below remain historical. Publication requires a
successful CI run for the corrected commit; the GitHub Release links that final run.
The remote tag was not published from the failed candidate.

## 1.0.0 release candidate — 2026-10-03

Rechecked the candidate with Xcode 27.0 (27A266a), Swift 6.4 in Swift 6 language
mode, and the dedicated iPhone 18 Pro / iOS 27.0 simulator. Production, test and
example sources match `f6f188bc`; release preparation changes documentation only.

| Check | Result |
| --- | --- |
| Complete package and UIKit integration suite | **150 tests in 13 suites passed**, 6.712 seconds |
| Public layout compiler checks | **5 passed**: one valid consumer and four expected compile failures |
| Production Release build, `arm64-apple-ios16.0` | Passed with `-warnings-as-errors` |
| Independent SwiftPM consumer | README quick start and injected diffable source passed in Release, targeting iOS 16, with `-warnings-as-errors` |
| IM / Store public-API example | Built; **all 10 UI smoke checks passed** |
| LayoutDemo | Built; **all six steps completed**, with 22 display callbacks |

The layout report confirmed Compositional item heights of 92 → 140 pt, Flow item
heights scaled by 1.25 with the content section moving from index 1 to 0, and the
external waterfall changing from two to three columns. Reports were checked for
fresh output from this run, not reused from earlier launches.

Artifacts: `/private/tmp/ParadeRelease-1.0.0.xcresult`,
`/private/tmp/ParadeRelease-1.0.0-smoke.json`, and
`/private/tmp/ParadeRelease-1.0.0-layout.json`. Build and compiler-check logs share
the `/private/tmp/ParadeRelease-1.0.0-` prefix. The independent consumer uses the
local package product; it does not validate a published 1.0.0 tag or remote resolution.

Production and independent-consumer builds emitted no warnings. The test build
retained two existing weak-variable mutability suggestions; test and LayoutDemo
builds emitted the App Intents metadata warning. All checks above completed successfully.

The remote CI checked during this review last passed for the 0.3.0 commit
`db4a8279`; it has not verified this candidate. Xcode 16.0 and 16.4 are not installed
locally, so minimum-toolchain and CI-runtime results remain pending. The iOS 16
deployment-target build is not iOS 16 runtime evidence. Real-device performance,
animation quality and Podcast application integration remain unverified.

## Data source boundaries — 2026-10-03

The complete suite passed **150 tests in 13 suites** in 6.734 seconds on Xcode 27.0 /
iOS 27.0, using the dedicated Parade simulator. Result bundle:
`/private/tmp/ParadeDataSource-01.xcresult`.

The public-import data-source fixture now performs granular content updates using
only the new model comparisons and `CollectionViews`. New checks cover retained
cell/header instances with changed content, equal-content behavior replacement,
layout-only geometry changes, same-ID cell and header type replacement, layout capture
identity versus derived stages, and source/views release. The fixture deliberately
reloads structural changes; it is not an independent general-purpose diff algorithm.
Both built-in factories also verify `CollectionViews` release. Existing structural
replay, captured-stage layout, FIFO, lifecycle and invalid-plan recovery tests passed.

All **five public-module compiler checks** passed: one positive assembly and four
expected failures. Both the standalone IM / Store app and the maintained LayoutDemo
Xcode project built against the refactored source. All **10 IM / Store UI smoke checks**
passed, including install-state updates across all three Store sections. Report:
`/private/tmp/Parade-datasource-smoke.json`. The LayoutDemo project's interactive
sequence was not repeated; layout runtime coverage comes from the full test suite.

The test build emitted the existing weak-variable suggestions; tests and the layout
example build emitted the App Intents metadata warning. No test or build failed.
No new minimum-toolchain, iOS 16 runtime, real-device performance or Podcast integration
verification was performed. Changes remain in one `Parade` target, with physical
source folders separating the responsibilities.

## Research cleanup — 2026-10-03

Removed the temporary layout and scroll-position research harnesses, their source
overlays, generated reports, and build artifacts. The maintained IM / Store and
layout example projects remain. Layout runtime regressions remain in the
public-import test suite; the standalone compiler checks now live at
`Tests/check_layout_types.py`, with CI and documentation updated to that path.

All five compiler checks passed after the move: one valid assembly and four expected
compile failures. This cleanup did not change production or runtime test source;
the full simulator suite was not rerun. Scroll-position experiments do not establish
a supported automatic position-preservation API.

## Typed layout integration — 2026-10-02

The final complete suite passed **147 tests in 13 suites**, with no failures or
skips, in 17.336 seconds on Xcode 27.0 / Swift 6.4 / iOS 27.0 (iPhone 18 Pro
simulator). Result bundle: `/private/tmp/ParadeLayouts-final-02.xcresult`.

The new public-import consumer module runs 14 parameterized scenarios through both
built-in data sources: heterogeneous concrete Flow sections/delegates, native Flow
defaults and self-sizing, layout-only updates, capture stability, FIFO submissions,
section/item moves and transfers, Compositional construction, an external pure Swift
waterfall protocol, typed Store reuse, captured delegate reuse/release, weak layout
access ownership, and application child-protocol array submissions. Existing binding,
lifecycle, update planning and diagnostics tests
continue to pass; scroll forwarding now also enters through the installed public delegate.

`python3 Tests/check_layout_types.py` passed the positive assembly check,
including application subprotocol arrays, and all four expected compile failures:
wrong Section layout family, wrong data-source family, nonconforming Flow delegate,
and overriding a reserved callback. This builds separate modules from current source
without `@testable`; output is `.build/LayoutAPIChecks/results.json`.

The new `Examples/LayoutDemo/LayoutDemo.xcodeproj` built and ran against the local
production package. Its six recorded steps verified 92 → 140 pt Compositional sizing,
80 → 100 pt Flow sizing with Section reorder, two → three waterfall columns, successful
revisions and actual display callbacks. Geometry report: `/private/tmp/ParadeLayoutDemo-results.json`.
The original IM / Store public-API app migrates its child-protocol array through a
per-element `collectionSection` property. A direct array upcast using an explicitly
constrained primary-associated child protocol compiled but crashed in `_arrayForceCast`
on this toolchain. The per-element path passes both data-source runtime tests; the
migration guide records this distinction rather than relying only on typechecking.
All **10 IM / Store UI smoke checks** passed, including the install action and its
shared state in all three Store sections. Report: `/private/tmp/ParadeExamples-layout-smoke.json`.
The simulator initially failed to load a system library after the earlier crash;
restarting this dedicated device restored launch, without erasing application data.

The full tests emitted weak-variable mutability suggestions and an App Intents
metadata warning. The standalone example linker now explicitly uses the simulator SDK,
removing the prior macOS sysroot warning.
No new minimum-Xcode or iOS 16 runtime verification was performed. CI now includes
the type checks and demo build, but has not been run remotely for this working change.
These results do not establish real-device performance, animation quality, or universal
third-party layout compatibility. Podcast itself has not been migrated or built.

## Public visibility and binding API — 2026-10-02

Collection visibility is now assigned through `isVisible`; cell and supplementary
behavior bindings use `bind(to:)`. The string logger was removed; diagnostics and
successful submissions remain observable through `onDiagnostic` and `onDidApply`.

The complete suite passed **133 tests in 12 suites** in 15.061 seconds on
Xcode 27.0 / iOS 27.0. The result bundle is
`/private/tmp/ParadePublicAPI-20261002.xcresult`.

Existing tests cover repeated and reentrant visibility changes, collection and
section display ordering, equal-content behavior replacement, both built-in data
sources, and public-import implementations of a separate data source and diff
algorithm. The standalone public-API examples also compiled targeting iOS 16
Simulator. No new tests were added for the mechanical API migration.

This run did not repeat the example UI smoke checks or validate iOS 16 runtime,
minimum-toolchain compatibility, or real-device behavior. Existing UIKit observation
feedback diagnostics and the standalone example's linker sysroot warning remain;
no check failed.

## Composable collection updates — 2026-09-28

Collection calls now describe a change with `compose` / `update`, optionally add
content selections with `updating`, and submit through `apply`. Section-owned
`update()` remains immediate. Async store reconciliation always reaches its apply
callback and accepts membership only after that callback succeeds.

The complete suite passed **133 tests in 12 suites** in 14.825 seconds on
Xcode 27.0 / iOS 27.0. The final result bundle is
`/private/tmp/ParadeChainFinal-20260928.xcresult`.

New coverage checks inert descriptions, fresh capture on repeated apply, independent
description copies, accumulating/deduplicated selections, a cell transfer into a new
section combined with content and order changes, queued capture versus the latest
unselected baseline, selection by instance identity, failure/retry without attachment
leaks, and diagnostics at the correct target section position. Combined transfers run
through both data sources in `.diff` and `.reload` modes. Store integration checks now
exercise unified content-only and structural submissions through the public API.
Existing lifecycle, stale-generation, reservation, reentrancy and queue tests also pass.

Standalone public-API examples compiled targeting iOS 16 Simulator, and all **10 UI
smoke checks** passed on iOS 27, including shared install-state updates across Store
sections. The report is `Documents/smoke.json` in the example app's data container.
These checks do not establish iOS 16 runtime behavior, minimum-toolchain compatibility,
real-device performance, or all animated visual transitions. Existing UIKit observation
feedback diagnostics, the weak-variable compiler warning and the example linker sysroot
warning remain; no check failed.

## Section controller naming — 2026-09-28

Renamed `SectionPresenter` to `SectionController`, its `updates` property to
`updateContext`, and section-store `presenters` accessors to `controllers`.
Section-related generic parameters, examples, and tests use the same terminology.
Submission methods, public access levels, and runtime behavior remain unchanged.

The complete suite passed **126 tests in 12 suites** in 14.751 seconds on
Xcode 27.0 / iOS 27.0. The result bundle is
`/private/tmp/ParadeControllerNaming-20260928.xcresult`. The standalone examples
compiled against the public API, targeting iOS 16 Simulator. This run did not repeat
the example UI smoke checks or verify older-runtime and real-device behavior.

The test log includes UIKit observation-tracking feedback-loop diagnostics; no test
failed. The standalone example build emitted the existing linker sysroot warning.

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
