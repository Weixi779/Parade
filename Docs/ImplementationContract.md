# Parade implementation contract

This records the implemented Presenter, diff and data-source boundaries (2026-09-17).

## Ownership

- The application creates `UICollectionView` and its system layout and owns business state.
- `SectionPresenter` exposes stable `id` and main-actor composition getters:
  `cells: [AnyCellPresenter]`, and `supplementaryViews: [AnySupplementaryPresenter]`.
  Empty sections are retained. Each section can produce any number of cell types.
- `CellPresenter` and `SupplementaryPresenter` retain generic identity/view types
  and ordinary content comparison, with main-actor configuration and behavior binding.
  Concrete presenters should be immutable values after submission.
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
  last applied baseline, serial updates, the delegate bridge, and registrations.
- The constructor's factory creates one `CollectionDataSource` instance retained by
  the orchestrator. It owns current data/positions and UIKit updates and supplies the
  stable native data source. View creation uses Parade's supplied providers.
- `DefaultCollectionDataSource` owns its algorithm, current sections and position
  indexes, batch execution, and reload recovery. Each `CollectionUpdatePlan` is a
  complete validated value; its batches contain operations and real section contents.
- `DiffableCollectionDataSource` uses Apple's native snapshots, with explicit content
  refresh and native position queries.
- UIKit callbacks resolve the version currently being presented. End-display callbacks
  resolve the presenter associated with the actual view, even after removal/reordering.

## Public API direction

`CollectionOrchestrator(collectionView:)` uses the default implementation;
`init(collectionView:makeDataSource:)` accepts an external factory. Supplying
`diffAlgorithm:` selects an algorithm within the default implementation.
The orchestrator accepts `[any SectionPresenter]` through
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
Erasers and internal plans carrying them are not Sendable. The public algorithm
remains generic, and its coordinate-only result is Sendable; do not add unchecked
Sendable to AnyHashable or UI closures.
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
  item, and preserve transfers across deleted/new sections. The Apple data-source
  implementation uses native diffing instead of this computation slot.
- Identity, visual-content equality, and view-registration compatibility are distinct.
  Compatible content updates use reconfiguration. A registration/type change replaces
  the view. Content changes never suppress updates to closures/behavior bindings.
- Presenters sharing a view type must overwrite or clear bindings they own. The
  default `setBehaviors` no-op does not clear previously installed actions.
- UIKit counts/data must match the result of each applied stage. Do not overlap batches.
- The default implementation issues no empty UIKit batch. Explicit reload and
  off-window updates install the latest composition using reloadData; the Apple
  implementation uses applySnapshotUsingReloadData.
- Data-source apply receives complete validated source/target compositions and
  finishes only when its UIKit work and current queries reach the target. The
  orchestrator then refreshes behaviors/layout and publishes completion. A custom
  source owns content refresh; the two supplied implementations share fixed rules.
- Current section/item queries belong to the data source. The orchestrator retains
  only the last completed baseline for the next apply, not a competing current index.
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

## Required verification

Build with Swift 6 for iOS. Independently replay structural plans, including section
reordering and cross-section moves. Exercise real collection views for heterogeneous
sections, self-sizing, content-only updates, behavior-only updates, same-Id view-type
changes, supplementary changes, empty sections, queued/reentrant updates, and callbacks
after removal. Runtime checks do not establish real-device performance or animation quality.
