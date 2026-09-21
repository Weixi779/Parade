# Changelog

## Unreleased — breaking changes

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
