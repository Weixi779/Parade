//
//  SimulatorApp.swift
//  ParadeExamples
//
//  Created by weixi on 2026/9/17.
//

import UIKit

@main
@MainActor
final class SimulatorAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SimulatorSceneDelegate.self
        return configuration
    }
}

@MainActor
final class SimulatorSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var smokeTask: Task<Void, Never>?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        let messages = UINavigationController(rootViewController: IMExampleViewController())
        messages.tabBarItem = UITabBarItem(
            title: "Messages",
            image: UIImage(systemName: "bubble.left.and.bubble.right"),
            tag: 0
        )
        let store = UINavigationController(rootViewController: AppStoreExampleViewController())
        store.tabBarItem = UITabBarItem(
            title: "Store",
            image: UIImage(systemName: "square.grid.2x2"),
            tag: 1
        )
        let tabs = UITabBarController()
        tabs.viewControllers = [messages, store]
        let startInStore = ProcessInfo.processInfo.arguments.contains("--store")
        tabs.selectedIndex = startInStore ? 1 : 0

        let window = UIWindow(windowScene: scene)
        window.rootViewController = tabs
        self.window = window
        window.makeKeyAndVisible()

        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            smokeTask = Task { @MainActor in
                await ExampleSmokeTest(tabs: tabs).run()
                tabs.selectedIndex = startInStore ? 1 : 0
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) { smokeTask?.cancel() }
}

/// The smoke test observes ordinary UIKit views and sends ordinary control actions.
/// It has no access to Parade internals or the example controllers' private state.
@MainActor
private final class ExampleSmokeTest {
    private struct Check: Codable {
        let name: String
        let passed: Bool
        let detail: String
    }

    private struct Report: Codable {
        let passed: Bool
        let checks: [Check]
    }

    private let tabs: UITabBarController
    private var checks: [Check] = []

    init(tabs: UITabBarController) { self.tabs = tabs }

    func run() async {
        if let previousReport = try? reportURL() {
            try? FileManager.default.removeItem(at: previousReport)
        }
        tabs.selectedIndex = 0
        if let messages = await collectionView(inTab: 0, expectedCounts: [2, 3]) {
            record("im.sectionCounts", true, "\(counts(in: messages))")
        } else {
            record("im.sectionCounts", false, "Expected [2, 3] before the 8-second deadline")
        }

        tabs.selectedIndex = 1
        if let store = await collectionView(inTab: 1, expectedCounts: [2, 4, 3]) {
            record("store.sectionCounts", true, "\(counts(in: store))")
            var classNames: [String] = []
            for section in 0..<3 {
                let cell = await visibleCell(at: IndexPath(item: 0, section: section), in: store)
                let className = cell.map { String(describing: type(of: $0)) }
                record(
                    "store.section\(section).visibleCell",
                    className != nil,
                    className ?? "No visible cell before deadline"
                )
                if let className { classNames.append(className) }
            }
            record(
                "store.distinctCellClasses",
                Set(classNames).count == 3,
                classNames.joined(separator: ", ")
            )
            await checkSharedInstallation(in: store)
            store.setContentOffset(
                CGPoint(x: -store.adjustedContentInset.left, y: -store.adjustedContentInset.top),
                animated: false
            )
        } else {
            record("store.sectionCounts", false, "Expected [2, 4, 3] before the 8-second deadline")
        }

        writeReport()
    }

    private func collectionView(
        inTab index: Int,
        expectedCounts: [Int]
    ) async -> UICollectionView? {
        guard let controller = tabs.viewControllers?[index] else { return nil }
        controller.loadViewIfNeeded()
        var found: UICollectionView?
        let ready = await waitUntil(seconds: 8) {
            controller.view.layoutIfNeeded()
            found = self.firstView(of: UICollectionView.self, in: controller.view)
            return found.map { self.counts(in: $0) == expectedCounts } ?? false
        }
        return ready ? found : nil
    }

    private func visibleCell(
        at indexPath: IndexPath,
        in collectionView: UICollectionView
    ) async -> UICollectionViewCell? {
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        let ready = await waitUntil(seconds: 3) {
            collectionView.layoutIfNeeded()
            return collectionView.cellForItem(at: indexPath) != nil
        }
        return ready ? collectionView.cellForItem(at: indexPath) : nil
    }

    private func checkSharedInstallation(in collectionView: UICollectionView) async {
        let featured = IndexPath(item: 0, section: 0)
        guard let cell = await visibleCell(at: featured, in: collectionView),
              let button = firstView(of: UIButton.self, in: cell.contentView) else {
            record("store.install", false, "Featured app's button did not appear")
            return
        }
        record(
            "store.initialInstallState",
            button.currentTitle == "Get",
            button.currentTitle ?? "No title"
        )
        button.sendActions(for: .touchUpInside)
        let installed = await waitUntil(seconds: 5) {
            collectionView.layoutIfNeeded()
            return collectionView.cellForItem(at: featured).flatMap {
                self.firstView(of: UIButton.self, in: $0.contentView)
            }?.currentTitle == "Open"
        }
        record("store.install", installed, "The tapped featured app changes from Get to Open")

        // The sample's Iris app also appears at ranking[0] and recommendations[1].
        for (name, indexPath) in [
            ("ranking", IndexPath(item: 0, section: 1)),
            ("recommendations", IndexPath(item: 1, section: 2)),
        ] {
            let cell = await visibleCell(at: indexPath, in: collectionView)
            let title = cell.flatMap { firstView(of: UIButton.self, in: $0.contentView)
            }?.currentTitle
            record("store.sharedInstall.\(name)", title == "Open", title ?? "No visible button")
        }
    }

    private func counts(in collectionView: UICollectionView) -> [Int] {
        (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
    }

    private func firstView<View: UIView>(of type: View.Type, in root: UIView) -> View? {
        if let view = root as? View { return view }
        for child in root.subviews {
            if let view = firstView(of: type, in: child) { return view }
        }
        return nil
    }

    private func waitUntil(seconds: TimeInterval, condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !Task.isCancelled {
            if condition() { return true }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            do { try await Task.sleep(nanoseconds: 30_000_000) } catch { return false }
        }
        return false
    }

    private func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(Check(name: name, passed: passed, detail: detail))
    }

    private func writeReport() {
        let report = Report(passed: checks.allSatisfy(\.passed), checks: checks)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: reportURL(), options: .atomic)
            print(
                "Parade examples smoke test: \(report.passed ? "passed" : "failed") (\(checks.count) checks)"
            )
        } catch {
            print("Could not write Parade examples smoke report: \(error)")
        }
    }

    private func reportURL() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("smoke.json")
    }
}
