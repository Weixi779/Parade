# Implementation verification

Verified locally on 2026-09-17 with Xcode 27.0 (27A266a), Swift 6 language mode,
and an iPhone 18 Pro / iOS 27.0 simulator.

- The Parade module builds for an iOS 16 simulator deployment target.
- All 55 Swift Testing tests pass in five suites. Parameterized tests additionally
  cover both animated/nonanimated updates and changed/unchanged prepared-view content.
- The pure planner suite independently replays 23,386 exhaustive/random transitions,
  plus focused cases. It checks operation sources/destinations rather than trusting
  a stage's declared result.
- UIKit integration covers self-sizing, content-only and behavior-only updates,
  same-Id cell type changes, cross-section moves with deleted/new endpoints, section
  reordering, retained empty sections, supplementary changes, dynamic header topology,
  invalid identity rejection, captured compositions, FIFO and reentrant updates.
- Bridge regressions cover retained/prepared cells and supplementary views entering
  display again without a new dequeue. Removed views keep their own final callbacks.
- Capability regressions cover each optional cell protocol through a generic erasure,
  combined capabilities, concrete-cell dispatch, default policies, and ignoring
  same-named methods without conformance. A UIKit regression removes and restores
  selection capability on a retained cell while preserving collection-wide events.
- A consumer-only test protocol survives erasure without registration in the Parade
  module. Policies are read on query, and UIKit interaction consumers use the newest
  policies and callbacks after an equal-content update, including menu coordinates.
- Supplementary display observation is opt-in. Tests cover generic erasure, concrete
  view adaptation, default callbacks, same-named methods without conformance, and a
  consumer-only supplementary capability unknown to the library. Existing UIKit
  regressions verify removed and redisplayed supplementary view bindings.
- Final full-run logs contain no UIKit registration debug assertion or unexpected
  test-runner exit.
- Class registration covers cached cell reuse across presenter types, same-Id view
  type replacement, and supplementary kind compatibility. Presenter registration
  configuration and nib construction have been removed.
- Basic erasure operations use protocol-extension bridges. Regression checks cover
  cross-presenter-type equality, incompatible views, and shared cell/header types
  explicitly clearing earlier actions. Registration preparation and dequeue remain
  in `ViewRegistry`, with native handlers configuring the current presenter.
- The separate public-import example app builds and passes all 10 smoke checks:
  IM section counts `[2, 3]`, App Store counts `[2, 4, 3]`, three distinct Store cell
  classes, and one installation action updating the same app's three occurrences.

Local result artifacts:

- Full tests: `/tmp/ParadeTests-erasure-cleanup.xcresult`
- Full test log: `/tmp/Parade-test-erasure-cleanup.log`
- Example app: `.build/Examples/ParadeExamples.app`
- Example smoke result: its simulator data container's `Documents/smoke.json`

Use the commands in the root README and Examples/README.md to reproduce the checks.

## Error recovery verification

A full run after adding recovery passed 51 Swift Testing tests in four suites on
the same iPhone 18 Pro / iOS 27.0 simulator. The run includes the current presenter
capability work as well as these recovery checks:

- Valid → invalid → valid submissions in both diff and reload modes preserve the
  applied baseline, invoke each completion once, and keep the queue progressing.
- An invalid first submission leaves an empty baseline and can be retried from its
  deferred diagnostic callback.
- Five injected planner faults cover a thrown error, an invalid later stage, an
  incomplete plan, duplicate intermediate IDs, and a missing intermediate presenter.
  All recover by reloading a valid target before any structural batch, then accept
  a subsequent update enqueued by the diagnostic callback.
- Real UIKit requests exercise empty-cell and missing-header fallbacks. The empty
  cell cannot forward business events even when a later presenter occupies its
  index path; an explicit reload restores its normal view. A normal subsequent
  header update restores the supplementary presenter.
- Production plan validation also runs over the existing 23,386 independently
  replayed transitions, plus malformed-coordinate/conflict and optional-ID cases.

Result: `/tmp/ParadeErrorHandlingTests-1.xcresult`.
Log: `/tmp/ParadeErrorHandlingTests-1.log`.
No tests failed and no UIKit registration assertion or test-runner crash appeared.
The example smoke checks listed above were not rerun for this recovery change.

## Equatable and planning extraction verification

A full run after migrating to `DiffableElement: Equatable` passed 63 Swift Testing
tests in six suites on the iPhone 18 Pro / iOS 27.0 simulator (9.848 seconds).
This includes the existing 23,386 independently replayed structural transitions,
all UIKit/capability and recovery regressions, and five new complete-planner tests:

- Every stage binds the correct structural result to source-version presenters,
  preserving existing metadata while supporting newly inserted sections and cells.
- Final content edits use target coordinates, including retained cells transferred
  from a removed section into a new section.
- Section reloads subsume item content edits; other sections still distinguish
  view replacement from visual reconfiguration.
- Equal-content results retain the target's newest behavior closures, and one
  differ can plan independent baselines without storing an applied target.
- Captured-input rejection preserves both duplicate occurrence locations.

Fixtures exercise both synthesized `Equatable` and custom nonisolated operators.
No isolated-conformance feature, unchecked sendability, or runtime actor assumption
was added. The structural Heckel algorithm and its move policy are unchanged.

Results: `/tmp/ParadeEquatableTests-1.xcresult`.
Log: `/tmp/ParadeEquatableTests-1.log`.
The test run has no UIKit assertion or runner crash; Xcode emitted its usual warning
that App Intents metadata extraction was skipped because the module has no dependency.

The public-import example app also builds with Swift 6 language mode for an iOS 16
simulator deployment target and passes all 10 smoke checks on iOS 27, including an
installation action updating the same app in three sections. A copy of the result
is at `/tmp/ParadeEquatable-smoke.json`; the build log is at
`/tmp/ParadeEquatable-example-build.log`. The standalone build emits a linker
sysroot warning, but simulator installation and execution both succeed.
Compilation with a Swift 6.0 compiler or execution on an iOS 16 runtime is not
established by this run.

## MainActor boundary verification

After narrowing isolation to UI requirements, all 64 tests in six suites pass on
the iPhone 18 Pro / iOS 27.0 simulator (9.818 seconds). The final run has no Swift
actor-isolation warnings, UIKit assertions, or runner crashes; Xcode still emits
the unrelated App Intents metadata extraction warning.

- A dedicated actor constructs and erases cell presenters, compares them, validates
  local compositions, and computes a complete changeset. Only scalar results cross
  the actor boundary; no Sendable conformance was added to erased presentation data.
- Pure planner tests run without suite-wide MainActor isolation. Tests that actually
  construct UIKit supplementary kinds or invoke UI behavior closures stay isolated.
- Existing UIKit, interaction-policy, generic capability, equal-content behavior,
  staged update, FIFO, and recovery tests pass with member-isolated protocols.
- An ordinary public-import client constructs and compares a synthesized-Equatable
  presenter successfully. A negative client that calls generic `configure` from a
  nonisolated function fails with the expected MainActor diagnostic.
- Mutable section fixtures retain their chosen MainActor ownership. A header fixture
  captures its UIKit default kind in an isolated initializer; ordinary equality is
  unchanged. Neither case requires whole-type isolation on the public protocol.

Final result: `/tmp/ParadeIsolationTests-2.xcresult`.
Final log: `/tmp/ParadeIsolationTests-2.log`.
Public API checks: `/tmp/parade-isolation-api-check/Values.swift` and
`/tmp/parade-isolation-api-check/InvalidUI.swift`, with corresponding `.log` files.

The public-import example app builds for the iOS 16 simulator deployment target
and passes all 10 smoke checks on iOS 27, including the shared installation action
across three sections. Smoke result: `/tmp/ParadeIsolation-smoke.json`.
Build log: `/tmp/ParadeIsolation-example-build-2.log`. This standalone build retains
the existing linker sysroot warning. Swift 6.0 compiler and iOS 16 runtime execution
remain unverified; the selected compiler is Swift 6.4 in Swift 6 language mode.

## Shared indexing verification

After extracting shared indexing, all 75 Swift Testing tests in eight suites pass
on the iPhone 18 Pro / iOS 27.0 simulator (9.867 seconds), using Swift 6.4 in Swift 6
language mode. This includes the existing 23,386 independently replayed structural
transitions and UIKit update, rejection, recovery, and actor-boundary regressions.

- Generic indexing covers first/last/custom resolution, accumulated values across
  three occurrences, single-pass input, one key projection per element, early
  rejection, Optional keys and nil values, and concrete error propagation.
- Incremental insertion keeps the previous lookup when duplicate rejection throws.
- Composition coverage checks presenter lookup contents, section ordering, section
  and cell identity scope, supplementary kind/section scope, invalid addresses,
  both conflict locations, and error precedence when input has several defects.
- Structural indexing checks source/target diagnostics and preserves the order of
  section and item validation. The matching and move policies are unchanged.

Result: `/tmp/ParadeIndexingTests-1.xcresult`.
Log: `/tmp/ParadeIndexingTests-1.log`.
The run has no Swift warnings, UIKit assertions, or runner crashes. Xcode emits
the existing App Intents metadata extraction warning. Subsequent edits only wrap
test declarations and update documentation; the affected Swift files parse.
The separate example smoke checks were not rerun for this internal extraction.
Swift 6.0 compiler compatibility and iOS 16 runtime execution remain unverified.

## Replaceable sectioned diff verification

The final full run passed **84 Swift Testing tests in nine suites** on 2026-09-17,
using Xcode 27.0 (27A266a), Swift 6 language mode and an iPhone 18 Pro / iOS 27.0
simulator. The run finished in 6.485 seconds. The module also builds for a generic
iOS Simulator destination with the package's iOS 16 deployment target.

- The public `SectionedDiffAlgorithm` consumes complete sections/items and returns
  original-coordinate membership, move and content changes. Public-import tests
  cover independent section/item equality, empty-section content, section moves,
  and move-plus-update transfers between deleted/new section endpoints.
- A second implementation uses Swift `CollectionDifference` and only `import Parade`.
  For a four-item rotation it selects one move where the default selects three.
  UIKit integration records that exact one move, reaches the target and performs no
  recovery reload, establishing that the default algorithm does not override it.
- The default path retains 23,386 exhaustive/random independently replayed transitions.
  Another 2,000 deterministic mixed transitions replay the alternate implementation
  through the same planner and independent replay helper.
- Malformed results cover bounds, identity mismatch, duplicate moves/updates, updates
  to new identities, missing reorder operations and omitted cross-section transfers.
  Five injected algorithm faults verify target reload before any batch and subsequent
  diagnostic-reentrant queue progress. Private stage preflight regressions remain.
- Existing UIKit, supplementary, registration, behavior binding, captured input,
  actor-boundary, FIFO and recovery tests pass. Presenter protocols are unchanged.

Result: `/tmp/ParadeSectionedDiffTests-2.xcresult`.
Log: `/tmp/ParadeSectionedDiffTests-2.log`.
The run contains no Swift warnings, UIKit assertions or test-runner crashes. Xcode
emits the existing unrelated App Intents metadata extraction warning. Subsequent
Swift edits only clarify complexity documentation. No example app smoke test or
performance benchmark was rerun; the checks above do not establish animation quality,
iOS 16 runtime behavior or compilation with a Swift 6.0 toolchain.

## Injectable data source verification

The final full run passed **86 Swift Testing tests in ten suites** on 2026-09-17,
using Xcode 27.0, Swift 6 language mode and the iPhone 18 Pro / iOS 27.0 simulator.
It finished in 6.544 seconds. The module builds for a generic iOS Simulator with
the package's iOS 16 deployment target.

- Thirteen existing integration tests now run against both the default manual
  implementation and the Apple diffable adapter. They cover content-only and
  behavior-only changes, self sizing, same-ID cell-type replacement, moved cells
  changing type across removed/new section endpoints, supplementary content/type/
  topology changes, capture, rejection, empty/off-window updates, FIFO reentrancy,
  and structural transitions with and without animation. Manual-operation assertions
  remain on the manual path; native tests assert current queries and visible results.
- A separate test file imports only `Parade`. An independent external data source
  receives the supplied providers and validated compositions without internal access.
  Suspending its first apply verifies that current queries stay with its current
  data, the next submission waits, and public completions remain FIFO.
- Both built-in factories run once, retain their implementation while the orchestrator
  lives, and release it afterward. Tests cover non-Sendable reference identities,
  movement, deletion/reinsertion, explicit reload, missing IDs and invalid positions.
- Default algorithm injection, invalid-plan recovery, independent structural replay,
  actor-boundary checks and actual-view lifecycle regressions remain covered.
  Presenter protocols are unchanged. The planner no longer repeats its caller's
  target in the returned changeset; behavior refresh remains verified at integration.

Result: `/tmp/ParadeDataSourceTests-4.xcresult`.
Log: `/tmp/ParadeDataSourceTests-4.log`.
There are no Swift warnings, UIKit assertions or runner crashes. Xcode emits the
existing App Intents metadata extraction warning. Later edits only clarify API
documentation and this report.

The standalone public-import example app also builds. IM uses the default source;
App Store injects the Apple adapter. All **10 UI smoke checks pass**, including the
shared install action updating all three App Store occurrences through native snapshots.
Report: `/tmp/ParadeDataSource-smoke.json`.
Build log: `/tmp/ParadeDataSource-example-build.log`.
The standalone build retains its existing linker sysroot warning.

No background diff scheduling or performance benchmark was added. These checks do
not establish device performance, animation quality, iOS 16 runtime execution or
compilation with the Swift 6.0 compiler. The installed compiler uses Swift 6 language
mode. Both supplied data source implementations currently execute on MainActor.

## Default implementation directory grouping

Ten Swift files were moved into their owning data-source directories. Before/after
SHA-256 checks confirm that their contents are unchanged. The default UIKit batch
planner and validators now live in `DataSource/Default/`; shared composition,
validation and content rules live directly in `DataSource/`.

The generic iOS Simulator build passed after the moves. Log:
`/tmp/ParadeDefaultSourceGrouping-build.log`. The move manifest with hashes is
`/tmp/ParadeDefaultSourceMoves.json`. Tests were not rerun for this path-only change;
the full functional verification above predates the moves.

## Unified update plan verification

After replacing the planner/stage wrappers with `CollectionUpdatePlan` and
`CollectionBatch`, the full run passes **80 Swift Testing tests in nine suites**
on the iPhone 18 Pro / iOS 27.0 simulator, using Xcode 27.0 in Swift 6 language
mode. It finished in 6.539 seconds. Generic iOS Simulator compilation also passes.

- Batches carry real section contents directly. The 23,386 default-algorithm
  transitions and 2,000 alternate-algorithm transitions still run through an
  independent identity replay oracle. Its surviving/moved values come from the
  source, not the batch's declared target. Optional IDs remain covered.
- Full-plan tests verify source content and supplementary metadata throughout
  structural movement, final target-coordinate content edits, registration changes,
  and planning using values local to a separate actor.
- Input validation now belongs to `CollectionComposition`. Existing tests retain
  duplicate scopes, supplementary constraints, both conflict coordinates, and the
  first-error precedence across sections, cells and supplementaries.
- The unused generic indexing API and its seven tests were removed. One new public
  algorithm test covers duplicate section/item IDs on both input sides, in addition
  to the existing position-lookup diagnostic tests. This accounts for 86 to 80 tests.
- Malformed algorithm results, incomplete moves, invalid/conflicting batch operations,
  reload recovery before UIKit mutation, FIFO reentrancy, and both data sources'
  UIKit regressions continue to pass. Public protocols and API declarations are
  unchanged by this internal refactor.

Result: `/tmp/ParadeUpdatePlanTests-2.xcresult`.
Log: `/tmp/ParadeUpdatePlanTests-2.log`.
Build log: `/tmp/ParadeUpdatePlan-build.log`.
The final run has no Swift warnings, UIKit assertions or runner crashes; Xcode still
emits its unrelated App Intents metadata extraction warning.

The standalone public-import example app builds and passes all **10 UI smoke checks**
with the default IM data source and injected Apple App Store data source.
Report: `/tmp/ParadeUpdatePlan-smoke.json`.
Build log: `/tmp/ParadeUpdatePlan-example-build.log` (the existing linker sysroot
warning remains). Later edits only update documentation. No new performance benchmark,
background scheduling, iOS 16 runtime run or Swift 6.0 compiler check was performed.

## Limits

iOS 16 runtime execution was not possible on this host: CoreSimulator reports that
the installed iOS 16.0 runtime is unsupported after macOS 26.99.99. Targeting iOS 16
with a newer SDK does not establish execution on iOS 16 or compilation with Xcode 16.
Class registration, view-type/kind compatibility keys, and API compilation are
covered. Device performance, scrolling/animation quality, real media/network
requests, and keyboard interaction are not established by these tests.
