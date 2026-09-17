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

## Limits

iOS 16 runtime execution was not possible on this host: CoreSimulator reports that
the installed iOS 16.0 runtime is unsupported after macOS 26.99.99. Targeting iOS 16
with a newer SDK does not establish execution on iOS 16 or compilation with Xcode 16.
Class registration, view-type/kind compatibility keys, and API compilation are
covered. Device performance, scrolling/animation quality, real media/network
requests, and keyboard interaction are not established by these tests.
