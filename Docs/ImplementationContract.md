# Parade implementation contract

This documents the 0.3 implementation (2026-09-23), including the API naming
changes from 0.2 and the compositional-only section model introduced in 0.2.

## Ownership and public input

- The application creates `UICollectionView`. `CollectionOrchestrator` installs its
  `UICollectionViewCompositionalLayout`, data source and delegate. There is no Flow
  forwarding or alternate-layout mode.
- `SectionPresenter` is a MainActor reference-type protocol: stable `id`, one stable
  `SectionUpdateContext`, and `captureContent()` with an associated output type.
  A section may own business requests/listeners. Its instance maps to one UIKit section.
- `SectionContent` is an output protocol requiring cells, supplementary views and
  `makeLayout(in:) -> NSCollectionLayoutSection`. The default supplementary list is empty.
  `DefaultSectionContent` offers convenience storage without restricting custom outputs.
- Outputs and their cell/supplementary values must remain immutable after capture. Layout
  methods use captured business inputs and the current UIKit environment, never live module state.
- `SectionSnapshot` erases concrete outputs for queued targets, completed baselines and
  intermediate stages. It includes mandatory native layout construction and exposes
  `DiffableSection` to pure planning. Replacing stage cells preserves its metadata/layout.
- Cell/supplementary identity, equality, registration, configuration, behavior replacement
  and optional interaction/display capabilities retain their existing responsibilities.
  Their erasers retain the original presenters; the layout contract does not use capability casts.

## Operations

- Optional `SectionStore.reconcile(_:)` resolves definitions and immediately accepts
  the resulting ordered instances. `reconcile(_:apply:)` first awaits its callback
  for structural changes, then accepts membership; unchanged membership skips that
  callback. Both return `Change` with target presenters, retained instances in target
  order, removals in previous order, and an instance/order change flag.
- Definition matching uses ID plus Input and Presenter types. New instances receive
  only `make(input)`; survivors receive the current `update(presenter, input)` even
  for repeated input. IDs must remain stable and match the definition. Duplicate IDs
  reject the full list before any definition closure executes. Removed instances are
  released by the store, and a returning identity is created again.
- Reconcile calls must be serialized and cannot reenter the store from callbacks.
  Callback failure preserves membership/order, not staged input or callback effects.
  A returned change retains its presenters and is not a display snapshot. The store
  retains no previous inputs or definition closures and never captures or submits
  presentations. The caller separately submits retained content through existing APIs.
- `setSections(_:animated:mode:completion:)` and its async overload change membership and
  order. Every supplied instance has a submission-time capture for possible attachment.
  At execution, surviving instances keep accepted content; absent instances use that capture,
  including the same instance rejoining after an earlier queued removal. Unused captures
  neither replace nor invalidate a survivor's accepted content.
- `section.update()` captures one attached module. `orchestrator.update(_:)` captures
  several modules atomically. Use the latter for cross-section cell transfers.
- `.diff` and `.reload` select UIKit execution strategy; they do not change an operation's
  membership/content meaning. The previous full-list `apply` API is removed.
- `setSections` validates member IDs and distinct update contexts at submission. Its
  captured content is conditional: an earlier operation may attach or remove an instance.
  Execution resolves membership, selects accepted content or the attachment capture,
  then validates the complete target. Unused captures cannot reject a reorder, including
  while initial attachment is queued or in progress. Content errors settle in FIFO order.
- Local `update` operations always use their captured outputs and validate them at
  submission. Execution checks attachment identity and validates the complete target.
- Section IDs are unique. Cell IDs identify globally unique display occurrences. Supplementary
  identity is section/kind-local; placement is section/kind/item. Empty sections remain present.
- New contexts are reserved before entering UIKit and become usable when attachment completes.
  One context belongs to one module instance. Removal/replacement disconnects old instances.
  Old queued operations cannot write into a replacement sharing the same business ID.

## Attachment and display

- `SectionAttachmentObserving` reports successful attachment and detachment after
  the update context is connected or disconnected. Reordering, content updates and
  rejected submissions do not create attachment transitions.
- Applications report containing-component visibility through `setVisible(_:)`,
  initially false. `CollectionDisplayObserving` follows it for every attached section,
  including offscreen sections. Visibility changes take effect during pending updates.
- `SectionDisplayObserving` additionally requires at least one displayed cell or
  supplementary view. Prepared views do not count. Content-driven transitions settle
  after all UIKit update stages, including same-ID replacement and cross-section moves.
- Entry order is attachment, collection display, then section display; exit reverses
  that order. Reentrant visibility changes are balanced after the current callback.
  Old view bindings carry attachment identity without retaining the section instance.
- Orchestrator destruction schedules remaining detachments on MainActor. Explicitly
  awaiting `setSections([])` completes cleanup before transferring section ownership.
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
  implement `CollectionDataSource`, including `layoutSection(at:environment:)`.
- Source `apply` receives validated complete source/target snapshots and returns after
  all UIKit work and current queries describe target. It owns content/layout stage installation,
  invalidation and recovery. View creation uses supplied native registration providers.
- The default source plans all structure before mutation. Manual structural batches retain
  source metadata/layout for surviving sections and target metadata/layout for new sections.
  The final content phase installs target metadata/layout. Layout-only updates perform a
  layout invalidation batch without forcing cell visual reconfiguration.
- The native source uses native snapshot positions, target content/layout and previous-version
  fallback during application. It invalidates and resolves the settled layout before returning.
- New captured layout versions invalidate even if cells are equal. No equality is required
  for UIKit layout objects or closures. Layout builders must handle empty/staged item counts.
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
