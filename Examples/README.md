# Parade examples

## Run the simulator app

From the repository root, build with the selected Xcode's iOS Simulator SDK:

```sh
python3 Examples/build.py
```

This compiles Parade as a separate static Swift 6 module, then compiles the app
using its public API. It writes an ad-hoc-signed app to
`.build/Examples/ParadeExamples.app`, which is ignored by Git. It requires Xcode
and Python 3; it does not generate an Xcode project or fetch dependencies.
The default architecture matches the Mac; use `--arch arm64` or `--arch x86_64`
when building for a different simulator architecture.

Choose a booted simulator and replace the placeholder with its device Id:

```sh
xcrun simctl list devices booted
PARADE_SIMULATOR_ID="YOUR_SIMULATOR_DEVICE_ID"
xcrun simctl install "$PARADE_SIMULATOR_ID" .build/Examples/ParadeExamples.app
xcrun simctl launch --terminate-running-process "$PARADE_SIMULATOR_ID" dev.weixi.parade.examples
```

Append `--store` to start on the Store tab. Append `--smoke-test` to run the
bounded UI checks:

```sh
xcrun simctl launch --terminate-running-process "$PARADE_SIMULATOR_ID" dev.weixi.parade.examples --store --smoke-test
```

The smoke test waits for IM section counts `[2, 3]` and Store counts `[2, 4, 3]`,
visits all Store sections to check their distinct cell classes, and sends the
featured app's install button action. It checks that the matching ranking and
recommendation occurrences also change to `Open`. It uses actual UIKit views
and collection counts without `@testable` or access to private controller state.

After the run, read its individual results from the application data container:

```sh
PARADE_EXAMPLE_DATA=$(xcrun simctl get_app_container "$PARADE_SIMULATOR_ID" dev.weixi.parade.examples data)
cat "$PARADE_EXAMPLE_DATA/Documents/smoke.json"
```

The report is cleared at smoke-test startup and written atomically on completion.
Each wait has a deadline; a normal successful run takes a few seconds. The app
stays open afterward for inspection.

## Use the controllers in another app

Add `ParadeExamples.swift` to an iOS 16+ application target that depends on the
`Parade` library. The file imports only Parade's public API and UIKit; it has no
application entry point and does not require `@testable` access.

`SimulatorApp.swift` supplies the standalone example's application entry point.
Do not add that file to a target that already has an app delegate or `@main` type.

Use either controller as an application's root, or present both in tabs:

```swift
let conversation = UINavigationController(rootViewController: IMExampleViewController())
conversation.tabBarItem.title = "Messages"

let store = UINavigationController(rootViewController: AppStoreExampleViewController())
store.tabBarItem.title = "Store"

let tabs = UITabBarController()
tabs.viewControllers = [conversation, store]
window.rootViewController = tabs
window.makeKeyAndVisible()
```

| Example | Section composition | Interactions |
| --- | --- | --- |
| IM | Yesterday and Today sections; text and attachment cell types within each section | Expand/collapse text, receive another message |
| App Store | Featured: 2 cells; Ranking: 4 cells; Recommendations: 3 cells; each section has its own model and cell type | Install an app and refresh every occurrence, select an app, scroll featured cards horizontally |

The IM example uses `CollectionOrchestrator(collectionView:)` with Parade's default
data source. The App Store example injects `DiffableCollectionDataSource` through
the initializer's factory closure. Both use the same Presenter protocols, view
providers, delegate handling, and public completion contract. The smoke test exercises
both implementations in the same app, including content updates on the Apple path.

The controllers own application state, the collection view, and the compositional
layout. Each section presenter produces the current typed cell presenters and a
header. The layout resolves section identity through `orchestrator.sectionId(at:)`,
which refers to the composition currently being displayed.

The same app appears in several Store sections. Its domain Id is shared, while
`StoreOccurrenceId(section:appId:)` identifies each cell occurrence. An installation
change therefore updates multiple independently presented cells.

The IM controller keeps expansion state outside the cell and presenter. New
presenters include that state in content comparison. `configure` writes visible
content; `setBehaviors` replaces the existing action closure, so an equal-content
update can still replace behavior without adding duplicate UIKit actions.

These are local UI demonstrations. Network requests, real media playback, keyboard
handling, navigation destinations, and scroll-position policies belong to the app
and are intentionally not implemented by the examples.
