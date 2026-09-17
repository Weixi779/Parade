# Changelog

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
