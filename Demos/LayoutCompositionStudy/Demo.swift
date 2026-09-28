// Created by weixi on 2026/10/02.

import Parade
import StudySupport
import UIKit

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Study", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = DemoController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

@MainActor final class DemoController: UIViewController {
    let log = EventLog()
    let values = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    let flow = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    let waterfall = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    lazy var valuesOwner = CollectionOrchestrator(collectionView: values, layout: .compositional())
    lazy var flowOwner = CollectionOrchestrator(collectionView: flow, layout: .flow())
    lazy var waterfallOwner = CollectionOrchestrator(collectionView: waterfall, layout: .waterfall())
    lazy var valuesSection = CompositionalCards(cards: cards)
    lazy var flowSection = FlowCards(cards: cards, log: log)
    lazy var banner = FlowBanner(log: log)
    lazy var waterfallSection = WaterfallCards(cards: cards)
    lazy var cards = [80, 150, 100, 190, 90, 130, 170, 110].enumerated().map {
        Card($0.offset + 1, height: CGFloat($0.element), log: log)
    }
    let titleLabel = UILabel()
    let subtitle = UILabel()
    let status = UILabel()
    let picker = UISegmentedControl(items: ["返回布局值", "Flow delegate", "自定义瀑布流"])
    let runButton = UIButton(type: .system)
    var running = false
    var samples: [[String: Any]] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.text = "Section 仍然拥有布局"
        titleLabel.font = .systemFont(ofSize: 27, weight: .bold)
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 2
        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.textColor = .systemIndigo
        status.numberOfLines = 2
        picker.selectedSegmentIndex = 0
        picker.addTarget(self, action: #selector(selectLayout), for: .valueChanged)
        runButton.setTitle("重播验证过程", for: .normal)
        runButton.addTarget(self, action: #selector(replay), for: .touchUpInside)
        for child in [titleLabel, subtitle, picker, status, values, flow, waterfall, runButton] { view.addSubview(child) }
        for collection in [values, flow, waterfall] { collection.backgroundColor = .systemBackground }
        selectLayout()
        Task {
            do {
                try await valuesOwner.compose([valuesSection]).apply(animated: false)
                try await flowOwner.compose([banner, flowSection]).apply(animated: false)
                try await waterfallOwner.compose([waterfallSection]).apply(animated: false)
                valuesOwner.isVisible = true
                flowOwner.isVisible = true
                waterfallOwner.isVisible = true
                if CommandLine.arguments.contains("--auto-demo") { await run() }
            } catch { status.text = "初始化失败：\(error)" }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width, top = view.safeAreaInsets.top
        titleLabel.frame = CGRect(x: 20, y: top + 12, width: width - 40, height: 36)
        subtitle.frame = CGRect(x: 20, y: top + 52, width: width - 40, height: 46)
        picker.frame = CGRect(x: 16, y: top + 112, width: width - 32, height: 34)
        status.frame = CGRect(x: 20, y: top + 156, width: width - 40, height: 44)
        for collection in [values, flow, waterfall] {
            collection.frame = CGRect(x: 0, y: top + 208, width: width, height: view.bounds.height - top - 270 - view.safeAreaInsets.bottom)
        }
        runButton.frame = CGRect(x: 16, y: view.bounds.height - view.safeAreaInsets.bottom - 48, width: width - 32, height: 40)
    }

    @objc func selectLayout() {
        let index = picker.selectedSegmentIndex
        values.isHidden = index != 0; flow.isHidden = index != 1; waterfall.isHidden = index != 2
        subtitle.text = ["Section 返回 NSCollectionLayoutSection\n布局值与内容一起捕获", "Section 提供具体的原生 Flow delegate\n多个 Section 共用一个 UICollectionView", "自定义 UICollectionViewLayout + 自有协议\n适配代码全部放在库外"][index]
        status.text = "相同的 compose → update → apply"
    }
    @objc func replay() { Task { await run() } }
    func pause() async { try? await Task.sleep(for: .seconds(2.5)) }

    func record<L>(_ name: String, owner: CollectionOrchestrator<L>, view: UICollectionView) {
        view.layoutIfNeeded()
        let frames = (1...8).compactMap { id -> [String: Any]? in
            guard let path = owner.indexPath(for: id), let rect = view.collectionViewLayout.layoutAttributesForItem(at: path)?.frame else { return nil }
            return ["id": id, "section": path.section, "item": path.item,
                    "x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
        }
        samples.append(["step": name, "revision": owner.appliedRevision, "frames": frames])
    }

    func run() async {
        guard !running else { return }
        running = true; runButton.isEnabled = false; picker.isEnabled = false
        defer { running = false; runButton.isEnabled = true; picker.isEnabled = true }
        samples = []
        do {
            valuesSection.height = 92; flowSection.scale = 1; flowSection.cards = cards
            waterfallSection.columns = 2; waterfallSection.cards = cards
            try await valuesSection.update(animated: false)
            try await flowOwner.compose([banner, flowSection]).updating([flowSection]).apply(animated: false)
            try await waterfallSection.update(animated: false)
            picker.selectedSegmentIndex = 0; selectLayout()
            status.text = "1 / 6 · 返回明确布局值：92 pt"
            record("value-initial", owner: valuesOwner, view: values)
            await pause()
            valuesSection.height = 140
            try await valuesSection.update(animated: true)
            status.text = "2 / 6 · 只改 Section 布局：140 pt"
            record("value-update", owner: valuesOwner, view: values)
            await pause()
            picker.selectedSegmentIndex = 1; selectLayout()
            status.text = "3 / 6 · 两个 Section、两种具体 Flow delegate"
            record("flow-initial", owner: flowOwner, view: flow)
            await pause()
            flowSection.scale = 1.25
            flowSection.cards.reverse()
            try await flowOwner.compose([flowSection, banner]).updating([flowSection]).apply(animated: true)
            status.text = "4 / 6 · Section + item 重排，同时更新尺寸"
            record("flow-reorder", owner: flowOwner, view: flow)
            await pause()
            picker.selectedSegmentIndex = 2; selectLayout()
            status.text = "5 / 6 · 库外自定义布局：双列瀑布流"
            record("waterfall-initial", owner: waterfallOwner, view: waterfall)
            await pause()
            waterfallSection.columns = 3
            try await waterfallSection.update(animated: true)
            status.text = "6 / 6 · Section 更新为三列，核心无需认识该协议"
            record("waterfall-three-columns", owner: waterfallOwner, view: waterfall)
            await pause()
            let document = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let result: [String: Any] = ["completed": true, "displayCallbacks": log.displayed.count, "samples": samples]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: document.appendingPathComponent("layout-study.json"))
            status.text = "完成 · 3 种布局 / 6 次状态记录\n调用处无需 any，Section 各自决定布局"
        } catch { status.text = "验证失败：\(error)" }
    }
}
