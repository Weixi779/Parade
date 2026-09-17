# Parade implementation contract

This is the first implementation boundary, agreed naming from the design discussion,
and the working contract between the implementation tasks (2026-09-17).

## Ownership

- The application creates `UICollectionView` and its system layout and owns business state.
- `SectionPresenter` is a public, main-actor protocol: stable `id`, current
  `cells: [AnyCellPresenter]`, and `supplementaryViews: [AnySupplementaryPresenter]`.
  Empty sections are retained. Each section can produce any number of cell types.
- `CellPresenter` and `SupplementaryPresenter` are main-actor protocols with generic
  identity and view types, explicit content comparison, configuration, and behavior
  binding. Concrete presenters should be immutable values after submission.
- Both erasers retain an internal `underlyingPresenter` and captured identity and
  registration information. Basic operations use internal protocol-extension bridges;
  erasers do not store forwarding closures. The orchestrator's `ViewRegistry` owns
  registration preparation, caching, and dequeue through internal generic helpers.
- Cells opt into `CellSelectionHandling`, `CellHighlightHandling`,
  `CellDisplayObserving`, and `CellContextMenuProviding` independently. These protocols
  refine `CellPresenter`; the core does not inherit them. Erasure retains the original
  value internally. Event consumers query its capabilities, and each capability owns
  adaptation to the presenter's concrete cell type. Policies are read when queried.
- Supplementary presenters opt into `SupplementaryDisplayObserving` independently
  of their base protocol. The eraser retains the original presenter internally;
  UIKit consumers query the capability from the bound view's presenter, with typed
  adaptation alongside the capability protocol.
- `CollectionOrchestrator` captures each submission's section composition, owns the
  last applied baseline, serial updates, UIKit data source/delegate, and registrations.
- UIKit callbacks resolve the version currently being presented. End-display callbacks
  resolve the presenter associated with the actual view, even after removal/reordering.

## Public API direction

`CollectionOrchestrator(collectionView:diffAlgorithm:)` accepts `[any SectionPresenter]` through
`apply(_:animated:mode:completion:)` and an async throwing overload. `mode` is `.diff`
or `.reload`. The application retains the orchestrator. Updates are FIFO; completion
means all stages, content, supplementary, and behavior refreshes have been applied.
Cancelling an awaiting caller does not roll back an already submitted UIKit update.

IDs are hashable, sections are unique in the collection, and cells are globally unique
display occurrences. The same domain entity in two sections needs distinct occurrence
IDs. Cross-section movement keeps its cell Id. Supplementary views are addressed by
section Id, element kind, and item index (default zero). Invalid submissions are rejected
before mutation. There is no required public Snapshot or whole-page presenter type.

MainActor belongs to UI operations and reads of live section/supplementary state,
not identity, equality, captured data, or planning. Presenter protocols isolate
individual UI requirements; `DiffableElement: Equatable` has no actor requirement.
Erasers are not Sendable. Pure structural diff types are generic
and conditionally Sendable; do not add unchecked Sendable to AnyHashable or UI closures.
The initial implementation computes small diffs synchronously and makes no benchmark
claim about background execution or superiority to Apple's data source.

## Update rules

- The public algorithm slot receives complete sections with identity/content and items,
  and returns section/item membership, movement and content changes. The default uses
  unique-Id matching with the existing greedy policy; LIS and minimal moves are not
  requirements. UIKit staging remains separate and preserves the supplied move choices.
- `DiffableSection` is a read-only computation contract. Its own-content comparison
  excludes items; the captured Parade input adapts it without changing presenters.
  Algorithm results use original source/target coordinates, include every new/removed
  item, and preserve transfers across deleted/new sections. No DataSource extension
  point is introduced in this change.
- Identity, visual-content equality, and view-registration compatibility are distinct.
  Compatible content updates use reconfiguration. A registration/type change replaces
  the view. Content changes never suppress updates to closures/behavior bindings.
- Presenters sharing a view type must overwrite or clear bindings they own. The
  default `setBehaviors` no-op does not clear previously installed actions.
- UIKit counts/data must match the result of each applied stage. Do not overlap batches.
- Empty diffs issue no empty UIKit batch. Explicit reload and updates while off-window
  install the latest composition using reloadData.
- Invalid submissions fail without advancing the applied baseline or blocking the
  queue. They are not silently deduplicated. The complete structural plan and its
  presenter mappings are checked before the first batch; planning failures reload
  only an independently validated target, then complete successfully.
- `onDiagnostic` reports rejected input, reload recovery, or an inert empty-view
  fallback. It runs outside UIKit data-source callbacks after active update state
  settles. Missing cell/supplementary presenters do not trigger explicit traps.
- Registration instances are cached and derived from concrete view types, plus the
  element kind for supplementary views. Only class registration is supported; there
  is no presenter registration property or nib/XIB construction path.
- The framework owns no network tasks, navigation, height cache, layout DSL, prefetch,
  drag/drop, or scroll-position policy.

## Work allocation

- Presenter task: `Sources/Parade/Cell/`, `Sources/Parade/Section/`,
  `Sources/Parade/Supplementary/`, and `Sources/Parade/Registration/`, with corresponding
  tests. Define typed protocols, erasers, and registration cache.
- Diff task: `Sources/Parade/Diff/` and structural diff tests. Pure UIKit-independent
  stage planning and independent replay validation.
- UIKit task: `Sources/Parade/UIKit/` delegate/data-source bridge and event forwarding.
- Integration task: orchestrator, captured display records, package test target, docs,
  and integration tests/examples for IM and App Store.

## Required verification

Build with Swift 6 for iOS. Independently replay structural plans, including section
reordering and cross-section moves. Exercise real collection views for heterogeneous
sections, self-sizing, content-only updates, behavior-only updates, same-Id view-type
changes, supplementary changes, empty sections, queued/reentrant updates, and callbacks
after removal. Runtime checks do not establish real-device performance or animation quality.
