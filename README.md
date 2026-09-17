# Parade

A modular UICollectionView framework for Swift.

Parade is under development. Its first implementation provides typed section,
cell, and supplementary presenters, a custom sectioned diff, and a UIKit update
orchestrator. It does not use `UICollectionViewDiffableDataSource`.

## Requirements

| Requirement | Minimum |
| --- | --- |
| Deployment target | iOS 16.0 |
| Swift tools | Swift 6.0 |
| Swift language mode | Swift 6 |
| Xcode | Xcode 16.0 |

iOS 16 is the baseline for native self-sizing invalidation. It also includes the
cell and supplementary registration APIs and item reconfiguration needed by the
planned UIKit integration. See Apple's [What's new in UIKit](https://developer.apple.com/videos/play/wwdc2022/10068/).

Swift 6 language mode enables full data-race safety checking. The tools version
remains 6.0 until implementation requires a newer language or package feature.
See [Announcing Swift 6](https://www.swift.org/blog/announcing-swift-6/).

## Package

The package exposes one library and module, `Parade`, with no external dependencies.
Add this directory as a local package in Xcode and select the `Parade` product.

```swift
import Parade
```

The application supplies the `UICollectionView` and layout and retains a
`CollectionOrchestrator`. It submits current `[any SectionPresenter]` compositions;
each section can hold any combination of `AnyCellPresenter` and
`AnySupplementaryPresenter`. Concrete presenters keep their typed model and view
relationship until that composition boundary.

```swift
struct MessagePresenter: CellPresenter {
    let id: UUID
    let text: String

    func configure(_ cell: UICollectionViewListCell) {
        var configuration = cell.defaultContentConfiguration()
        configuration.text = text
        cell.contentConfiguration = configuration
    }
}

struct ConversationPresenter: SectionPresenter {
    let id: UUID
    let messages: [MessagePresenter]
    var cells: [AnyCellPresenter] { messages.map(AnyCellPresenter.init) }
}

// Retain this as a property of your view controller.
let orchestrator = CollectionOrchestrator(collectionView: collectionView)
try await orchestrator.apply([conversationPresenter], animated: true)
```

Section IDs are unique in the collection. Cell IDs identify globally unique display
occurrences; an app shown in two App Store sections needs two occurrence IDs.
Presenters should remain immutable after submission. Business state, actions,
requests, navigation, and scrolling policy remain in the application.

`CellPresenter` and `SupplementaryPresenter` inherit `DiffableElement: Equatable`.
Identity matches occurrences; standard `==` decides whether matched values need
visual reconfiguration. The simple presenter above uses synthesized equality.
When a presenter stores closures, implement `static func == (lhs: Self, rhs: Self) -> Bool` using its presentation fields. Do not implement equality using
only the ID: a retained ID can have changed visual content. Including the ID in
synthesized or custom equality is fine, since diff content comparisons already
match IDs first.

Identity, equality, cell erasure, and captured diff data have no MainActor
requirement. Presenter protocols isolate UI configuration, behaviors, interaction
policies, and callbacks at the member level, without isolating the conforming type.
Ordinary value presenters therefore need no `nonisolated` equality workaround.

Reading a section's cells/supplementaries stays on MainActor because these getters
may read application UI state. Reading supplementary `elementKind` and its erasure
initializer also stay there: UIKit's standard header/footer constants require it.
Captured supplementary IDs, kinds, and item indices are ordinary values afterward.

The orchestrator, bridge, and registration registry retain their UI isolation. Diff
planning remains synchronous when called by the orchestrator; removing isolation
does not schedule background work. Presenter erasers are not Sendable, and this
change adds no isolated-conformance feature or runtime actor assumption.

Put replaceable button actions
and other closures in `setBehaviors(_:)`; Parade refreshes them even when content
compares equal. A same-Id change of view registration replaces the view safely.
Presenters sharing a view type must overwrite or clear bindings they own, including
setting an unused action to `nil`. The default `setBehaviors` implementation does
not clear actions installed by a previous presenter.

Cell interaction and visibility are opt-in capabilities. Keep a static presenter
conforming only to `CellPresenter`; add the capabilities it actually handles:

```swift
extension MessagePresenter: CellSelectionHandling {
    func didSelect(_ cell: UICollectionViewListCell) {
        // Forward the action to the application's state owner.
    }
}
```

| Capability | Provides |
| --- | --- |
| `CellSelectionHandling` | Selection/deselection policy and callbacks |
| `CellHighlightHandling` | Highlighting policy and callbacks |
| `CellDisplayObserving` | Display/end-display callbacks |
| `CellContextMenuProviding` | Context menu configuration |

Supplementary presenters opt into visibility callbacks with
`SupplementaryDisplayObserving`, using their concrete `View` type. Plain headers
and footers can conform only to `SupplementaryPresenter`.

`AnyCellPresenter` and `AnySupplementaryPresenter` retain the original presenter
behind its base protocol. Event consumers discover capabilities from that value;
each capability adapts UIKit's view to its concrete type. Adding an internal
capability and consumer does not require modifying the central eraser. The original
value remains internal.

The erasers keep the underlying presenter and captured identity/registration
information. Basic operations use internal protocol-extension bridges instead of
stored forwarding closures. `ViewRegistry` owns registration preparation and
dequeue, recovering each presenter's concrete view type through generic helpers.

Merely declaring a same-named method does not enable a capability. Without the
corresponding capability, selection, deselection, and highlighting remain allowed,
presenter callbacks do nothing, and context menus are absent. Collection-wide
selection event handling remains available. Policies are read when queried, rather
than captured during erasure; keep policy getters cheap and free of side effects.

Updates execute in FIFO order. Callback and async completion include every
structural stage, content update, and behavior refresh. A cancelled awaiting task
does not roll back an accepted update. Read-only queries describe the data source
version currently presented by UIKit; `onDidApply` and `appliedRevision` identify
completed submissions.

Invalid IDs or supplementary placements reject that submission and preserve the
current display; later valid submissions continue normally. Parade does not choose
between duplicate presenters. Callback failures and the async throwing API report
the rejection. If a valid target cannot be safely diffed, Parade reloads it before
starting any batch and completes successfully after the reload.

Set `onDiagnostic` to observe the reason, recovery action, and conflicting input
positions. Diagnostics are delivered outside UIKit callbacks after active update
state has settled, and may enqueue another submission. Missing cell/supplementary
presenters receive inert, dequeued empty views and a diagnostic instead of an
explicit framework trap.

Views use native class registration, derived automatically from each presenter's
concrete view type. Nib/XIB construction is unsupported.

Supported integration includes header/footer/custom
supplementary views, selection/highlighting, context menus, display callbacks,
scroll and FlowLayout delegate forwarding, empty content, and explicit `.reload`.
Empty sections are retained. The package has no third-party dependencies.

See [architecture and update semantics](Docs/Architecture.md),
[implementation boundary](Docs/ImplementationContract.md), and
[IM and App Store examples](Examples/ParadeExamples.swift).
The [verification report](Docs/Verification.md) records the tested paths and limits.

## Replacing the diff algorithm

The default `SectionedDiff` compares complete sections and their items. Supply another
`SectionedDiffAlgorithm` when creating the orchestrator:

```swift
let orchestrator = CollectionOrchestrator(
    collectionView: collectionView,
    diffAlgorithm: MySectionedDiff()
)
```

An implementation receives `[Section: DiffableSection]` for both input versions.
Section identity and `isContentEqual(to:)` describe the section itself; `items`
provide `DiffableElement` identity and content equality. Section comparison excludes
item content. Captured Parade data already supplies this contract, so existing
section/cell/supplementary presenter protocols need no changes.

Return `SectionedChanges` in original source/target coordinates. Deletions use source
positions; insertions and updates use target positions; moves contain both. Include
all new/removed items even inside new/deleted sections. Match globally retained item
IDs across sections, and allow an item to move and update together. Different valid
move lists are supported; source-order survivors must fill the remaining target slots.

Parade validates the structural result, translates it into UIKit batches, handles
view replacement/reconfiguration, and finishes content and behavior updates. The
algorithm receives no UI execution responsibility. Errors or invalid results fall
back to the captured valid target. Computation is synchronous; no background execution
or minimal-move guarantee is implied.

The [standard-library test implementation](Tests/ParadeTests/StandardLibraryDiff.swift)
uses only public API and demonstrates a second move policy. The production default
remains `SectionedDiff`.

## Development

Open `Package.swift` in Xcode, or build for a generic iOS destination:

```sh
xcodebuild -scheme Parade -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/ParadeDerivedData CODE_SIGNING_ALLOWED=NO build
```

Run Swift Testing and UIKit integration tests on an available iOS simulator:

```sh
xcodebuild -scheme Parade -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
    -derivedDataPath /tmp/ParadeDerivedData CODE_SIGNING_ALLOWED=NO test
```

Use a simulator name or Id available on your machine. `swift build` on macOS
targets macOS, where UIKit is unavailable; use an iOS destination for this package.
Structural tests independently replay more than 23,000 transitions. UIKit tests
cover data versions, reuse, self-sizing, supplementary updates, and reentrant
submissions. These are functional checks, not real-device performance benchmarks.

## License

Parade is available under the Apache License 2.0. See [LICENSE](LICENSE).
