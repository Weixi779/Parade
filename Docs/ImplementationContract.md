# Parade implementation contract

This documents the development API as of 2026-10-03, including replaceable data sources,
typed layout integration, section-controller naming and composable collection updates. See
[layout integration](LayoutIntegration.md) for concrete adapters and migration.

## Ownership and public input

- The application creates `UICollectionView`. `CollectionOrchestrator` installs its
  selected native layout, data source and delegate. A collection has one `Layout`
  association; Compositional and Flow are included, and custom integrations live outside core.
- `SectionController` is a MainActor reference-type protocol: stable `id`, one stable
  `SectionUpdateContext`, and `captureContent()` with an associated output type.
  A section may own business requests/listeners. Its instance maps to one UIKit section.
- `SectionContent` is an output protocol requiring cells, supplementary views and
  an associated `Layout` value through `@MainActor var layout`. The default supplementary
  list is empty. `LayoutContent<Layout>` offers convenience storage. `Content.Layout`
  must match the controller, collection, data source and store layout association.
- Outputs and their cell/supplementary values must remain immutable after capture. Layout
  queries use captured business inputs and the current UIKit environment, never live module state.
- `SectionSnapshot` erases concrete outputs for queued targets, completed baselines and
  intermediate stages, while preserving their layout type. It includes a captured layout value;
  an adapter alongside the staged implementation supplies `DiffableSection` to pure planning.
  Replacing stage cells preserves its metadata/layout version.
- Cell/supplementary identity, equality, registration, configuration, behavior replacement
  and optional interaction/display capabilities retain their existing responsibilities.
  Their erasers retain the original presenters; the layout contract does not use capability casts.
- Cell and supplementary presenter protocols own `Id`, `id` and `Equatable` directly.
  They do not inherit `DiffableElement`. Model operations expose view compatibility,
  supplementary content/compatibility and layout-version comparison to all data sources.

## Operations

- Optional `SectionStore.reconcile(_:)` resolves definitions and immediately accepts
  the resulting ordered instances. `reconcile(_:apply:)` awaits its callback for every
  valid reconciliation, including content-only changes and empty lists, then accepts
  membership. Both return `Change` with target controllers, retained instances in target
  order, removals in previous order, and an instance/order change flag.
- Definition matching uses ID plus Input and Controller types. New instances receive
  only `make(input)`; survivors receive the current `update(controller, input)` even
  for repeated input. IDs must remain stable and match the definition. Duplicate IDs
  reject the full list before any definition closure executes. Removed instances are
  released by the store, and a returning identity is created again.
- Reconcile calls must be serialized and cannot reenter the store from callbacks.
  Callback failure preserves membership/order, not staged input or callback effects.
  A returned change retains its controllers and is not a display snapshot. The store
  retains no previous inputs or definition closures and never captures or submits
  presentations. The callback can submit membership and retained content together with
  `compose(change.controllers).updating(change.retained).apply()`.
- `compose(_:)` and `update(_:)` construct a `CollectionUpdate` without capture or queueing.
  It is a value description retaining its collection and sections. `updating(_:)` adds
  selections, deduplicated by instance. Copies are independent; each `apply` captures fresh
  content. Animation and update mode are chosen at apply. The callback overload requires
  a completion; async apply awaits the same boundary.
- A composition specifies complete membership and order. At apply, every supplied instance
  is captured for possible attachment. At execution, unselected survivors keep accepted
  content; selected survivors and absent instances use their captures. This includes the
  same instance rejoining after an earlier queued removal. Unused captures neither replace
  nor invalidate a survivor's accepted content. Selected instances must belong to the target.
- `section.update()` still immediately captures and submits one attached module.
  `orchestrator.update(sections).apply()` submits several attached modules together without
  changing membership. Attachment is checked at apply, not description construction.
- A combined composition/content change builds one complete target and validates it before
  reservation or UIKit work. It is one queued submission, revision and completion, allowing
  cell transfers to newcomers without validating an intermediate membership-only target.
- `.diff` and `.reload` select UIKit execution strategy; they do not change an operation's
  membership/content meaning. Old collection `setSections` and immediate `update` are removed.
- Applying a composition validates member IDs, distinct update contexts and selection
  membership. Unselected captured content is conditional: an earlier operation may attach
  or remove an instance.
  Execution resolves membership, selects accepted content or the attachment capture,
  then validates the complete target. Unused captures cannot reject a reorder, including
  while initial attachment is queued or in progress. Conditional content errors settle
  in FIFO order. Selected content is always used and is locally validated at apply.
- Content-only operations additionally capture the attachment generation. Execution checks
  that identity and validates the complete target against the latest completed baseline.
- Section IDs are unique. Cell IDs identify globally unique display occurrences. Supplementary
  identity is section/kind-local; placement is section/kind/item. Empty sections remain present.
- New contexts are reserved before entering UIKit and become usable when attachment completes.
  One context belongs to one module instance. Removal/replacement disconnects old instances.
  Old queued operations cannot write into a replacement sharing the same business ID.

## Attachment and display

- `SectionAttachmentObserving` reports successful attachment and detachment after
  the update context is connected or disconnected. Reordering, content updates and
  rejected submissions do not create attachment transitions.
- Applications report containing-component visibility through `isVisible`,
  initially false. `CollectionDisplayObserving` follows it for every attached section,
  including offscreen sections. Visibility changes take effect during pending updates.
- `SectionDisplayObserving` additionally requires at least one displayed cell or
  supplementary view. Prepared views do not count. Content-driven transitions settle
  after all UIKit update stages, including same-ID replacement and cross-section moves.
- Entry order is attachment, collection display, then section display; exit reverses
  that order. Reentrant visibility changes are balanced after the current callback.
  Old view bindings carry attachment identity without retaining the section instance.
- Orchestrator destruction schedules remaining detachments on MainActor. Explicitly
  awaiting `compose([]).apply()` completes cleanup before transferring section ownership.
  Display observation does not itself cancel business work or measure exposure/occlusion.

## Queue and completion

- An unbounded AsyncStream holds complete submissions. One MainActor consumer awaits each
  operation through UIKit, behavior refresh, baseline/membership commit and completion.
- The operation constructs its target from the execution-time completed baseline. No local
  update or reorder operation can carry a stale whole-page presentation over another update.
- Every accepted operation has one completion. Failure preserves the baseline and processing
  continues. Enqueue termination is an explicit error. Cancelling a caller does not undo an
  accepted UIKit update; the caller's receipt still settles.
- Public queries describe the data source's current UIKit stage. The orchestrator separately
  holds the last completed baseline; it is not a competing current-position index.

## Data source and layout

- Construction calls the `makeDataSource` factory once and retains its result. Custom sources
  implement `CollectionDataSource`, including `sectionSnapshot(at:)`. The factory receives
  `(UICollectionView, CollectionViews)`; both belong to this collection only.
- Source `apply` receives validated complete source/target snapshots and returns after
  all UIKit work and current queries describe target. It owns content/layout stage installation,
  invalidation and recovery. Native dequeue callbacks use the supplied `CollectionViews`.
- After target installation, `CollectionViews.reconfigureSupplementaries(_:)` configures
  existing compatible views at target coordinates and invalidates layout once if any changed.
  Identity, placement or view-type changes require the source's reload path. Behavior binding
  remains the orchestrator's final step after source `apply`; equal visual content still rebinds.
  The views object retains neither source nor orchestrator and stores no snapshot history.
- `StagedCollectionDataSource` plans all structure before mutation. Manual structural batches retain
  source metadata/layout for surviving sections and target metadata/layout for new sections.
  The final content phase installs target metadata/layout. Layout-only updates perform a
  layout invalidation batch without forcing cell visual reconfiguration.
- The native source uses native snapshot positions, target content/layout and previous-version
  fallback during application. It invalidates and resolves the settled layout before returning.
- New captured layout versions invalidate even if cells are equal. No equality is required
  for UIKit layout objects or closures. Layout builders must handle empty/staged item counts.
  `hasSameLayoutVersion(as:)` compares capture identity; `replacingCells(_:)` keeps it.
- Planning failures reload an independently validated target before issuing any invalid batch.
  Diagnostics are delivered outside dequeue callbacks. Missing views use inert native fallbacks.

## Isolation and limits

- Section owners, output capture, UI callbacks and UIKit execution are MainActor-isolated.
  Identity, cell equality, captured-data reconstruction and diff planning remain nonisolated.
  Captured values are not Sendable and no unchecked conformance is introduced.
- The replaceable algorithm stays generic and coordinate-based; it owns no UIKit staging,
  layout invalidation, operation queue or recovery. Both supplied sources execute on MainActor.
- Attached modules are retained independently of cell visibility/reuse. Business cancellation,
  navigation, event routing, pagination, eviction and scroll anchoring remain application-owned.
  No generic layout family, second layout implementation or global event bus is included.
- UIKit owns cell reuse and native cell prefetching. Parade leaves `isPrefetchingEnabled`
  unchanged and does not install a `prefetchDataSource`; applications may supply one.
  Section working-range callbacks are outside the 0.3 API.

## Verification

Build for iOS with Swift 6. Verify captured layout-only changes on real collection views,
independent queued module updates, sorting without content replacement, stale-instance rejection,
global-conflict failure followed by success, atomic cell transfer, attachment reservation,
structural-stage layout identity, existing view lifecycles and both data-source implementations.
Run the public-API IM/Store examples and their smoke checks. Local simulator results do not
establish iOS 16 runtime behavior, device performance, or CI on a different Xcode toolchain.


## Layout ownership

- `CollectionLayout<Layout>` creates one native layout and one `CollectionLayoutDelegate`
  per collection. Its factories run once. The orchestrator retains the delegate and the
  collection retains the native layout; do not replace either installed object directly.
- `LayoutAccess<Layout>` weakly references the orchestrator and queries the current data
  source stage. After owner release queries return nil. Adapters must not query live Store
  arrays for positions. The layout remains responsible for geometry and invalidation rules.
- `CollectionLayoutDelegate` seals existing interaction/display/scroll callbacks and
  forwards them to the internal, non-generic view bridge. Subclasses add layout queries,
  including pure Swift protocols. Internal view binding is not a public extension surface.
- `FlowSectionLayout` retains a lazily constructed native Flow delegate for one capture
  and access. Use fresh payloads per capture, copying business settings before creation.
  Only six Flow layout queries are dispatched; optional methods fall back to native defaults.
- Custom data sources return a captured section for the same stage as their item counts,
  IDs and presenters. They must invalidate after installing a changed layout version.
  Pure sectioned diff algorithms remain independent of the layout type.
- No automatic scroll-position preservation, mixed native layout families, or universal
  third-party delegate forwarding is implied by this integration.
