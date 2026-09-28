# Changelog

## Unreleased

### Section controller naming

Stable section owners are now named controllers, distinguishing their business
state and lifecycle from immutable cell and supplementary presenters.

| Previous name | New name |
| --- | --- |
| `SectionPresenter` | `SectionController` |
| `SectionPresenter.updates` | `SectionController.updateContext` |
| `SectionStore.presenters` | `SectionStore.controllers` |
| `SectionStore.Change.presenters` | `SectionStore.Change.controllers` |

Update section conformances and store accessors to these names. `SectionDefinition`
now calls its section type parameter `Controller`; creation and update closures
retain the same signatures and behavior. Section examples use controller names.
The old names are not retained as aliases. This rename does not change runtime behavior;
the collection submission changes below are a separate API change.

### Composable collection updates

Collection changes are now descriptions with one explicit execution point:

| Previous call | New call |
| --- | --- |
| `setSections(sections, animated: false)` | `compose(sections).apply(animated: false)` |
| `update(sections, animated: false)` on the orchestrator | `update(sections).apply(animated: false)` |
| Structural submission followed by retained-content submission | `compose(sections).updating(retained).apply()` |

`CollectionUpdate` captures nothing until `apply`, which captures current content and
enqueues one combined target. Repeated `updating` calls accumulate distinct instances;
reapplying the description captures fresh content. Unselected survivors keep their
accepted content. Selections outside a composition fail with `sectionNotInComposition`.
Combined submissions support transferring a cell to a new section without an invalid
intermediate target. The callback `apply` overload requires a completion; the async
overload awaits the same full submission. Old collection entry points are removed.

Section-level `update()`, `updateContext`, `captureContent()` and lifecycle protocols
are unchanged. `SectionStore.reconcile(_:apply:)` now calls its callback for every
valid reconciliation, including unchanged membership and empty targets. Submit
`compose(change.controllers).updating(change.retained).apply()` inside that callback;
remove the old follow-up content submission. Membership is accepted after success;
failure preserves membership but does not roll back staged business input.

## 0.3.0

Optional section reconciliation preserves live module state across changing inputs.
Attachment and display callbacks let modules manage work at the corresponding lifecycle.

### API naming changes

The public access levels and extension points remain unchanged. Update conformances
and call sites using this mapping; the old names are not retained as aliases.

| Previous name | New name |
| --- | --- |
| `SectionPresentation` | `SectionContent` |
| `DefaultSectionPresentation` | `DefaultSectionContent` |
| `SectionPresenter.Presentation` | `SectionPresenter.Content` |
| `capturePresentation()` | `captureContent()` |
| `CapturedSection` | `SectionSnapshot` |
| `CollectionComposition` | `CollectionSnapshot` |

Content describes a module's display output; snapshots hold identified display versions
for queued updates and data sources. The new `SectionStore` owns live instances.

### Additions

- Add optional `SectionStore` and `SectionDefinition` for reconciling changing inputs
  into stable section instances. Matching ID, input type, and presenter type preserve
  local state; membership acceptance can await an external structural submission.
- Add `SectionAttachmentObserving` for successful attachment and detachment.
  Reorders and content updates preserve the attachment; rejected submissions emit no events.
- Add `CollectionDisplayObserving`, driven by the application's `setVisible(_:)`,
  and `SectionDisplayObserving`, which additionally requires a displayed cell or
  supplementary view. Callbacks handle reentrant visibility changes, same-ID instance
  replacement, delayed view callbacks, and updates without intermediate display flicker.
- Cover reconciliation through the public API, including ownership, failure/retry,
  suspended acceptance, and presentation integration with both supplied data sources.

### Lifecycle integration

Retain the store when using reconciliation, serialize its calls, and separately submit
retained sections' content with `orchestrator.update(_:)`. Failed structural submission
preserves store membership but does not roll back business input already received.

Forward the containing component's visibility to `orchestrator.setVisible(_:)` when
using section or collection display observation. Visibility defaults to false and
does not detach sections. Remaining attachments are cleaned up in a subsequent
MainActor task when the orchestrator is released; explicitly await `setSections([])`
to finish detachment before transferring modules to another collection.

### Verification

Local release checks passed 126 tests in 12 suites and all 10 public-API example
smoke checks on Xcode 27 / iOS 27. The minimum requirements remain iOS 16 and
Swift tools 6.0. These simulator checks do not establish iOS 16 runtime behavior
or real-device performance. See [verification coverage and limits](Docs/Verification.md).

## 0.2.0

Sections now own their state, captured compositional layout, and local updates.

### Breaking changes

- `CollectionOrchestrator` now installs and exclusively supports a compositional layout.
  Flow-layout forwarding and application-owned layout routing are removed.
- `SectionPresenter` is a MainActor reference-type contract with stable identity,
  `SectionUpdateContext`, and `capturePresentation()`.
- `SectionPresentation` requires native `NSCollectionLayoutSection` construction;
  `DefaultSectionPresentation` supplies convenience storage. `CapturedSection`
  replaces the former fixed `SectionContent` data-source input.
- `setSections` changes members/order while preserving surviving instances' accepted
  presentation. `section.update()` and `orchestrator.update(_:)` submit local or
  atomic multi-section content/layout updates. The old whole-page `apply` entry is removed.
- Complete operations run through one AsyncStream consumer. Targets use the latest
  completed baseline, validate global IDs at execution and reject stale module instances.
- Both built-in data sources expose stage-correct layout output and invalidate for
  layout-only updates. Custom sources must implement `layoutSection(at:environment:)`.
- IM and Store examples now retain section instances and submit module updates.

### Migrating from 0.1

- Keep each section as a stable class instance with its own `SectionUpdateContext`.
  Implement `capturePresentation()` using `DefaultSectionPresentation` or a custom
  immutable `SectionPresentation` output.
- Use `setSections` to attach, remove, or reorder sections. Await initial attachment,
  then use `section.update()` for content/layout changes or `orchestrator.update(_:)`
  to update several sections atomically. Reordering surviving instances preserves
  their accepted content; it does not submit their uncommitted live state.
- Move section layout construction into the captured presentation's `makeLayout(in:)`.
  Capture layout inputs with the cells; do not read mutable section state from the
  layout builder. Remove Flow-layout delegate forwarding and page-level layout routing.
- For custom data sources, consume `CapturedSection` through `CollectionComposition`
  and implement `layoutSection(at:environment:)` for the version currently used by UIKit.
- Cell and supplementary presenter configuration, behavior, and display capabilities
  retain their existing contracts. Attached sections remain alive independently of
  cell visibility; UIKit continues to own view reuse and native cell prefetching.

### Verification

Local release checks passed 89 tests in 10 suites and all 10 public-API example
smoke checks on Xcode 27 / iOS 27. The deployment target remains iOS 16; iOS 16
runtime behavior and real-device performance are not established by these checks.

See the [quick start](README.md#quick-start) and
[verification coverage and limits](Docs/Verification.md).

## 0.1.0

First public release of Parade, a modular `UICollectionView` framework for Swift.

### Features

- Typed section, cell, and supplementary presenters, with heterogeneous cells and
  sections composed through type erasure.
- Separate visual content and behavior updates, plus opt-in selection, highlighting,
  display callbacks, and context menus.
- An injectable `CollectionDataSource` factory with two supplied implementations:
  Parade's default staged updates and Apple's diffable data source adapter.
- A replaceable sectioned diff algorithm with section/item insertions, deletions,
  moves, content changes, and cross-section item transfers.
- Validated update plans, serialized UIKit updates, explicit reloads, invalid-input
  diagnostics, and reload recovery when a valid target cannot be safely diffed.
- Native cell and supplementary registration, self-sizing support, empty content,
  delegate forwarding, and view-bound lifecycle callbacks.
- Runnable IM and App Store examples demonstrating both data source implementations.

### Requirements and scope

- iOS 16+, Swift 6 language mode, and Swift tools 6.0+.
- One Swift Package Manager library, with no external dependencies, under Apache 2.0.
- Both supplied data sources execute on MainActor. No background diff scheduling,
  nib/XIB loading, prefetching, drag/drop, or automatic scroll anchoring is included.
- The application owns business state, layout, requests, and navigation.

### Verification

Local verification passed 80 tests in nine suites, including 25,386 independently
replayed structural transitions, and all 10 example UI smoke checks on iOS 27.
See [verification coverage and limits](Docs/Verification.md) and the
[CI runs](https://github.com/Weixi779/Parade/actions/workflows/ci.yml).

During 0.x development, minor versions may change public API. Use an up-to-next-minor
dependency requirement to stay on the 0.1 release line.
