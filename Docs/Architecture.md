# Architecture

Parade expresses a collection as a current composition of typed presenters. The
application owns its state and creates the collection view and system layout.
Parade owns the last applied composition and the mechanics of presenting the next one.

Construction chooses the update implementation explicitly:

```mermaid
flowchart LR
    App[Application] -->|makeDataSource closure| Factory[Create one CollectionDataSource]
    Factory -->|retained instance| Orchestrator[CollectionOrchestrator]
    Orchestrator -->|instance.dataSource| UIKit[UICollectionView.dataSource]
```

The factory receives the collection view and Parade's cell/supplementary providers.
It returns either `DefaultCollectionDataSource`, `DiffableCollectionDataSource`, or an
application implementation. There is no backend-type branch in the orchestrator.

## Public roles

| Role | Owns | Does not own |
| --- | --- | --- |
| SectionPresenter | Section identity and its current cells/supplementaries | Old section versions, requests, update queue |
| CellPresenter | One occurrence's identity, content comparison, concrete cell configuration and behaviors | Collection indexing or other sections |
| SupplementaryPresenter | Reusable-view identity, kind/item address, configuration and behaviors | Layout creation or cell lifetime |
| CollectionOrchestrator | Validated submissions, last completed baseline, FIFO queue, registry, delegate bridge, final completion | Current data-source positions, diff execution or UIKit batches |
| CollectionDataSource | Current section/item queries, native data source, applying a captured target through UIKit | Business state, submission queue, delegate or view-creation policy |
| DefaultCollectionDataSource | Current stage data and indexes, sectioned diff/planning, UIKit batches and reload recovery | Public completion or business events |
| DiffableCollectionDataSource | Native snapshots and positions, logical/native identity mapping, current and previous presenter lookup during apply | Parade's structural planner or its algorithm slot |

## Source ownership

- `DataSource/Default/` contains the default data source, `CollectionUpdatePlan`,
  `CollectionBatch`, and plan validation. A batch directly owns the section contents
  it presents; no separate identity structure or presenter-binding stage is built.
  These UIKit update rules are not part of the replaceable algorithm contract.
- `DataSource/` contains the shared protocol, captured composition and input validation,
  shared content-update rules, and the Apple implementation. Both implementations
  consume these types, so they do not belong exclusively to the default source.
- `Diff/` contains the public algorithm/input/result contracts, the default algorithm,
  and its shared identity-position lookup. It does not contain UIKit batch planning.
- `UIKit/` contains the fixed view/delegate bridge; `Registration/` owns native
  registration and dequeue.

The default implementation has three roles: the data source executes updates,
`CollectionUpdatePlan` constructs a complete validated update, and `CollectionBatch`
contains one batch's operations and its actual data. Plan validation is an extension
of that value, not another service or state owner.

## Presenter composition

Sections are protocol implementations, not subclasses of a framework controller.
An App Store section can transform one business model into two, four, or any number
of cells. A chat section can hold heterogeneous text, image, and notice presenters.
The same two layers support both cases. No separate whole-page presenter or public
snapshot type is required.

`AnyCellPresenter` and `AnySupplementaryPresenter` erase at the heterogeneous array
boundary. They retain an internal `underlyingPresenter`, along with captured
identity, address, and registration compatibility information. Basic operations
use internal protocol-extension bridges: configuration and behavior binding restore
the concrete view type, while equality checks the concrete type and casts the other presenter to `Self`.
The erasers store no forwarding closures. `DiffableElement: Equatable` supplies the
shared identity/equality contract. The erasers compare the same concrete presenter
type through standard `==`; concrete presenters can synthesize equality or provide
an ordinary `static func ==` for presentation fields while excluding behavior closures.
Identity, equality, captured data, and diff planning have no MainActor requirement.
The erasers have no `Sendable` conformance.
The public algorithm remains generic over section and item types. Its change result
is Sendable. The default update plan carries captured presenters and is not Sendable;
its constructor is synchronous and nonisolated. No unchecked sendability is applied
to UIKit or AnyHashable.

`CellPresenter` requires identity, a concrete cell type, visual content comparison,
configuration, and replaceable behavior binding. Selection, highlighting, display
observation, and context menus are independent opt-in protocols refining that core:
`CellSelectionHandling`, `CellHighlightHandling`, `CellDisplayObserving`, and
`CellContextMenuProviding`. They reuse the presenter's concrete `Cell` type.
The core protocol does not inherit them. `AnyCellPresenter` retains the original
value as an internal `any CellPresenter`, including when constructed through a
generic function constrained only to `CellPresenter`. It does not enumerate optional
capabilities or cache their callbacks. Event consumers query the capability from
the actual view binding; extensions alongside each capability restore the concrete
cell type before invoking its requirements. Incompatible cells are ignored.
An internal capability and its consumer can be added without changing the eraser.
This does not expose the original value or an event plugin API to applications.

Supplementary views follow the same boundary: `SupplementaryPresenter` owns
identity, element kind/item address, configuration, and behavior binding.
`SupplementaryDisplayObserving<View>` separately opts into visibility callbacks.
`AnySupplementaryPresenter` retains an internal `any SupplementaryPresenter` and
does not cache or forward display callbacks. UIKit consumers query the observer
from the actual view binding, and the capability extension restores the concrete
`View` type. Same-named methods without conformance are not invoked.

The existing public `shouldSelect`, `shouldDeselect`, and `shouldHighlight` queries
are extensions alongside their capability protocols. They read the underlying
policy when queried instead of capturing a Boolean at erasure time. Policy getters
should be cheap and free of side effects. Capability casts now happen when consumed;
no performance comparison with the previous cached callbacks has been established.

Absent capabilities mean no presenter callbacks and no context menu. Selection,
deselection, and highlighting policy defaults remain `true`, so collection-wide
event handling does not require a presenter-level selection handler. Opted-in
selection/highlighting protocols also default their policies to `true` and their
callbacks to no-ops; display callbacks default to no-ops. Context menu providers
must implement their configuration method and may return `nil` for a given request.

## Isolation boundary

Presenter and capability protocols place MainActor on specific UI requirements:
configuration, behavior binding, interaction-policy reads, and event callbacks.
Their conforming types are not implicitly isolated as a whole. Application code
can still choose MainActor for a section that owns mutable UI state.

`SectionPresenter.cells` and `supplementaryViews` are read on MainActor, and
`SectionContent.init(_:)` captures them there. Supplementary `elementKind` is also
read there because UIKit's header/footer constants are isolated in the SDK;
`AnySupplementaryPresenter.init(_:)` captures that value once. Identity itself,
cell erasure, captured section reconstruction, validation, and the complete differ
are ordinary synchronous value operations. `CollectionComposition.empty` creates
an empty value on access rather than sharing a non-Sendable global instance.

Orchestrator state, the bridge's view records, registration, and UIKit execution
remain MainActor-owned. The bridge's immutable binding values need no isolation.
Pure planning can be performed in another actor using values created within that
actor, without declaring erased presenters Sendable or moving UIKit views.
Both supplied data sources execute on MainActor. The default constructs its update
plan synchronously; the Apple adapter awaits native snapshot application. Neither path
adds background scheduling. Native integer identifiers satisfy the SDK's Sendable
identity constraints without declaring erased presenters or AnyHashable Sendable.

## Three independent comparisons

1. **Identity:** Is this the same logical display occurrence?
2. **Registration compatibility:** Can the same concrete reusable view represent it?
3. **Content equality:** Does the existing view need visual reconfiguration?

Same identity and different registration means replacement. Same registration and
changed content means reconfiguration. Equal content still installs current behavior
closures; do not include action closures in content equality merely to force this.
`setBehaviors` should replace bindings rather than append new targets on each update.
When presenters share a view type, each must overwrite or clear the bindings it
owns. A default no-op does not remove previously installed actions. Behavior binding
therefore remains a base requirement with explicit cleanup responsibility.
Transient view animation state need not become domain state. Persistent expansion,
selection, and similar application decisions should flow from application state.

Section IDs are unique. Cell IDs are globally unique occurrence IDs, allowing actual
cross-section moves. Supplementary identity is local to section and kind; its UIKit
address is `(sectionId, elementKind, itemIndex)`. Invalid duplicates or placements
are rejected before UIKit is touched. Native hashable equality applies to erased IDs;
use domain Id wrappers when otherwise-equal values represent different identities.

## Applying a submission

```mermaid
sequenceDiagram
    participant App
    participant Orchestrator
    participant Source as Selected DataSource
    App->>Orchestrator: apply section presenters
    Note over Orchestrator: Capture, validate, enqueue, prepare registrations
    Orchestrator->>Source: await apply(last completed, target)
    Note over Source: Own current data and UIKit update until settled
    Source-->>Orchestrator: Finished, optional recovery diagnostics
    Note over Orchestrator: Refresh behaviors/layout, commit baseline and revision
    Orchestrator-->>App: Completion
```

`CollectionComposition` and `SectionContent` expose the existing captured input to
external implementations. Callers still submit section presenters; they do not need
to build a public snapshot. The composition is complete, including identity, content,
and supplementary information. UIKit callbacks and public position queries read the
selected data source, never the orchestrator's last completed baseline.

For a cell request, the path is deliberately small:

```mermaid
flowchart LR
    UIKit[UIKit requests cell] --> Source[Selected DataSource resolves presenter]
    Source --> Provider[Supplied cell provider]
    Provider --> Registry[Registry dequeues and configures]
    Registry --> Binding[Bridge binds actual cell]
```

The bridge also handles UIKit delegate callbacks. It retains bindings on actual
views so an old disappearing view keeps the right presenter for its end-display
callback. Events reach the presenter's application callback; business state changes
produce a new submission. No context object is passed into business presenters.

## Default implementation's planning boundary

```mermaid
classDiagram
    class DefaultCollectionDataSource {
        <<public>>
        Current data and UIKit execution
    }
    class CollectionUpdatePlan {
        <<internal>>
        Complete validated update
    }
    class CollectionBatch {
        <<internal>>
        Operations and displayed section contents
    }
    class SectionedDiffAlgorithm {
        <<public>>
        Replaceable difference calculation
    }
    class CollectionContentUpdates {
        <<internal>>
        Shared view update rules
    }
    DefaultCollectionDataSource --> SectionedDiffAlgorithm : retains
    DefaultCollectionDataSource ..> CollectionUpdatePlan : constructs per update
    CollectionUpdatePlan ..> SectionedDiffAlgorithm : uses
    CollectionUpdatePlan *-- CollectionBatch : contains
    CollectionUpdatePlan *-- CollectionContentUpdates : contains
```

`CollectionComposition` validates identities and supplementary addresses in its
constructor while building immutable presenter lookups. Validation finishes each
section before proceeding to the next, preserving the first reported error and both
conflict positions. Only successful compositions enter the queue or become a reload
target. There is no separate input-index object or generic dictionary builder.

`CollectionPositions` is an internal calculation helper shared by the algorithm and
plan validation. It maps identities to positions and rejects duplicate section/item
identities with source/target coordinates. It owns no applied state. Input composition
validation keeps its own traversal and diagnostics because supplementary constraints
and error precedence belong to the captured composition.

`SectionedDiffAlgorithm` is the public computation boundary. It receives two arrays
of `DiffableSection`, including their items. Sections supply identity and comparison
of their own content; items use the existing `DiffableElement` identity and equality.
`SectionContent` adapts the captured presenters without changing presenter protocols.
Its own-content comparison covers supplementary identity, address and content, excluding cells.

`SectionedChanges` contains section/item inserts, deletes, moves and updates in the
original source/target coordinates. Item membership lists include items inside new
and deleted sections. A retained item crossing section identities is a move, including
transfers between deleted and inserted sections. A move may also have a content update.
The result contains no UIKit batches, intermediate data or reload/reconfigure decisions.

`SectionedDiff` is the default implementation. It matches unique IDs and uses a greedy
next-unconsumed-source policy, with expected linear matching work/storage plus input
hashing/comparison costs, and no minimal-move guarantee. `CollectionOrchestrator(collectionView:diffAlgorithm:)` accepts any implementation.
The algorithm runs synchronously; the input's comparison rules still define content equality.

`CollectionUpdatePlan` invokes the supplied algorithm and validates its result before
using any coordinates. It constructs up to three structural batches with complete
`SectionContent` values. Each retained section keeps its source supplementary metadata,
and each retained cell keeps its source presenter, even when moved into a new section.
Inserted identities use target content. Final content edits use target coordinates.

Each `CollectionBatch` stores operations and the exact contents the data source must
expose during those operations. There is no identity-only section model, outer stage
wrapper, or subsequent presenter reconstruction. `CollectionUpdatePlan+Validation`
replays batch operations against the previous contents and compares identities to
verify membership, coordinates, conflicts, move completeness, and final order.
Content comparison completeness remains the algorithm's responsibility.

The plan preserves supplied retained-identity moves and never recalculates a default
diff. An inserted section may need an extra move from its temporary insertion position.
Planning owns no applied state, queue, collection view, or recovery policy. A throwing
constructor cannot return a partially validated plan. Even an empty plan installs the
newest target presenters before the shared behavior refresh.

The default data source owns stage data, indexes, UIKit execution and reload recovery.
Algorithm errors or invalid results recover by reloading the validated target before
the first batch. The orchestrator owns the completed baseline and public completion.

`CollectionContentUpdates` holds the fixed view-update rules shared by both supplied
implementations. The default supplies its algorithm's content-change results; the
Apple adapter compares captured content directly and marks native snapshot reloads
or reconfigurations. Compatible supplementary updates configure visible views and
invalidate layout. Supplementary topology or registration changes reload the section.
The Apple adapter has no Parade structural stages: native snapshot APIs determine
positions, while target and previous presenter lookups resolve native requests until
apply completes. Removed identity mappings and the previous composition are released
after completion.

## Update lifecycle

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Queued: capture and validate submission
    Queued --> Preparing: prior submission completed
    Preparing --> Applying: invoke selected data source
    Applying --> Behaviors: UIKit update reaches target
    Behaviors --> Completed: refresh bindings and finish layout
    Completed --> Queued: pending submission
    Completed --> Idle: queue empty
```

Accepted submissions are FIFO. `apply` captures section composition before returning,
so a later change to the caller's array or section properties cannot change UIKit's
counts. Presenter values themselves must remain immutable after submission; the
framework cannot deep-copy arbitrary reference models captured inside user code.

The update plan contains up to three nonempty structural batches: add destination sections,
change/transfer items while section coordinates are stable, then delete/reorder
sections. No-op structure creates no batch; ordinary item changes fit in one batch.
The unique-Id Heckel move policy does not promise a minimal move count.

In the default implementation, each UIKit stage installs its resulting structure in the data source.
Existing cell content stays associated with the source version during structural
movement. After structure settles, content/registration changes are applied in a
separate phase to avoid unsafe reload/move combinations. Supplementary topology or
registration changes reload their section; compatible supplementary content is
configured on the existing view and invalidates layout. This is a deliberate UIKit
tradeoff: topology changes can replace otherwise unchanged cells in that section.

The orchestrator asks its `ViewRegistry` to prepare registration objects before
executing UIKit callbacks. The registry opens the underlying presenter's generic
type and owns preparation, caching, and dequeue directly; erasers do not route calls
back into it. The native cell handler uses the current erased presenter supplied by
UIKit, and supplementary configuration uses the presenter supplied for that dequeue.
Preparing registrations lazily inside the first dequeue callback is not sufficient,
even if later dequeues reuse the registration.
Only native class registration is supported. The framework derives registration
from the presenter's concrete view type and the supplementary element kind;
presenters do not expose registration configuration.

Display callbacks use bindings attached to the actual view. A removal or registration
change leaves the old binding available for its final `didEndDisplaying`. Visibility
does not imply entity insertion/deletion or own asynchronous request lifetime. New
compatible behaviors are also installed when a prepared cell enters display.
UIKit may display a previously prepared cell again without a new dequeue; see
[Apple's cell lifecycle discussion](https://developer.apple.com/videos/play/wwdc2021/10252/).

`sectionId(at:)`, `cellPresenter(at:)`, and identity/position queries use UIKit's current
stage. Compositional layout should resolve section identity through those queries,
not assume that its numeric index already refers to the application's latest array.
Use `supplementaryPresenter(ofKind:at:)` to decide whether that stage provides a
header/footer/custom view when supplementary topology changes with application state.
`appliedRevision` increments and `onDidApply` fires only after the entire submission.
Enqueuing from callbacks is supported. Cancelling a task awaiting `apply` leaves the
accepted update in the queue and does not cancel or roll back a UIKit transaction.

## Error recovery

Validation errors describe invalid input; the orchestrator owns recovery. Duplicate
IDs or invalid supplementary placements reject the whole submission, including
explicit reload submissions. Parade keeps the current display and reports failure
without advancing `appliedRevision`. Later valid submissions continue from the last
successfully applied composition. It does not guess which duplicate is authoritative.

Before the first structural batch, the default implementation replays the complete proposed plan to
check identities, coordinates, conflicts, intermediate counts and final structure.
It also prepares every intermediate presenter composition. A failed plan or missing
mapping reloads the independently validated target before any batch has started.
Only after execution completes does the queue update its baseline, advance the
revision, emit `onDidApply`, and complete successfully. Invalid input is rejected before entering the queue, without committing a target.

`CollectionDiagnostic` carries a reason, recovery action and, for invalid input,
the relevant positions. `onDiagnostic` and the diagnostic logger run after active
submission state settles. Diagnostics raised in UIKit data-source callbacks are
buffered, so the application can submit again without reentering a dequeue. A
successful reload recovery produces a diagnostic and successful completion; it is
distinct from rejecting an invalid target.

Missing cell content produces an inert reusable cell. Missing supplementary content
produces an inert reusable view registered for the layout-requested kind. Both use
UIKit dequeue APIs, including for previously unknown supplementary kinds, following
[Apple's supplementary dequeue contract](https://developer.apple.com/documentation/uikit/uicollectionview/dequeuereusablesupplementaryview(ofkind:withreuseidentifier:for:)).
Fallback views have no presenter binding and do not forward business events. Layout
space may remain empty until a subsequent update/reload supplies valid content.

These paths handle invalid compositions and planner/presenter lookup failures.
They do not intercept traps or exceptions raised by application-provided layout,
cell construction, configuration or event callbacks.

## What the source review contributed

| Project | Relevant design lesson | Parade choice |
| --- | --- | --- |
| [ReactiveCollectionsKit](https://github.com/jessesquires/ReactiveCollectionsKit) | Typed cell/supplementary models assembled by section, central driver | Keep these roles as presenters with our own update backend |
| [Epoxy](https://github.com/airbnb/epoxy-ios/blob/master/Sources/EpoxyCollectionView/Models/ItemModel/AnyItemModel.swift) | Separate content configuration and behavior binding | Explicit `configure` and `setBehaviors` |
| [Carbon](https://github.com/ra1028/Carbon/blob/master/Sources/Updaters/UICollectionViewUpdater.swift) | Its empty-diff path still installs data and can render visible components | No-op visual content cannot suppress new actions |
| [ComposedUI](https://github.com/composed-swift/ComposedUI) | Sections compose typed configuration and optional interaction capabilities | First-class section protocol; app still composes state |
| [Listable](https://github.com/square/Listable/blob/main/ListableUI/Sources/Item/ItemContentCoordinator.swift) | Entity callbacks and view visibility callbacks are distinct | Display callbacks have no implied business/task lifetime |
| [IGListKit](https://github.com/Instagram/IGListKit/blob/main/Source/IGListKit/IGListAdapterUpdater.m) | Inflight update state owns when the next transaction can begin | Explicit serialized submission queue |
| [DifferenceKit](https://github.com/ra1028/DifferenceKit/blob/master/Sources/Extensions/UIKitExtension.swift) | A valid diff still needs staged UIKit operations and per-stage data | Separate pure planning from UIKit execution |

These are selective design references, not dependencies or an assertion of feature
parity. The earlier RCK probe reproduced a crash for a same-Id registration change;
Parade has a runtime regression for that case. The benchmark discussion selected
Heckel as an implementation baseline, not as proof of a complete performance win.

## Initial limits

- iOS 16 minimum, Swift tools/language mode 6.0; the installed toolchain is newer.
- Collection views and layouts are application-owned. Select a data source in the
  factory; do not replace it or the delegate during use. Set the explicit forwarding delegates.
- No network/request ownership, layout DSL, height cache, navigation, prefetch API,
  drag/drop, interactive reordering, or automatic IM scroll anchoring is provided.
- Pending updates are not coalesced; every accepted update has its own completion.
- Cells and supplementary views must support class construction. Nib/XIB loading
  is not supported.
- Tests establish structural and UIKit functional correctness for their covered
  scenarios. They do not establish device performance or animated visual quality.
