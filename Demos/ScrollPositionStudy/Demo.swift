// Created by weixi on 2026/09/29.

import Parade
import UIKit

// Research harness only. Compensation deliberately runs after public apply completes.
// It does not change Parade or claim to keep every animation frame stationary.

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Demo", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = DemoController()
        window.overrideUserInterfaceStyle = .light
        self.window = window
        window.makeKeyAndVisible()
    }
}

private let ink = UIColor(red: 0.10, green: 0.15, blue: 0.23, alpha: 1)
private let accent = UIColor(red: 0.10, green: 0.37, blue: 0.89, alpha: 1)

@MainActor
private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = ink) -> UILabel {
    let view = UILabel()
    view.text = text
    view.font = .systemFont(ofSize: size, weight: weight)
    view.textColor = color
    view.numberOfLines = 0
    return view
}

private struct Row: CellPresenter {
    let id: Int
    var height: CGFloat = 64
    func configure(_ cell: RowCell) {
        cell.title.text = id == 21 ? "正在读 · 第 21 条" : id == 900 ? "上方的推荐模块" : id < 0 ? "刚插入的内容 \(-id)" : "第 \(id) 条内容"
        cell.subtitle.text = id == 21 ? "观察这张蓝色卡片的位置" : "稳定的内容身份，不随排序改变"
        cell.contentView.backgroundColor = id == 21 ? accent : UIColor(red: 0.94, green: 0.96, blue: 0.99, alpha: 1)
        cell.title.textColor = id == 21 ? .white : ink
        cell.subtitle.textColor = id == 21 ? .white.withAlphaComponent(0.85) : .secondaryLabel
        cell.accessibilityIdentifier = String(id)
    }
}

private final class RowCell: UICollectionViewCell {
    let title = label("", size: 16, weight: .semibold)
    let subtitle = label("", size: 11)
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.addSubview(title)
        contentView.addSubview(subtitle)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        title.frame = CGRect(x: 14, y: 10, width: bounds.width - 28, height: 22)
        subtitle.frame = CGRect(x: 14, y: 34, width: bounds.width - 28, height: 18)
    }
}

@MainActor
private final class Section: SectionController {
    let id: String
    let updateContext = SectionUpdateContext()
    var rows: [Row]
    init(_ id: String, rows: [Row]) { self.id = id; self.rows = rows }
    func captureContent() -> DefaultSectionContent {
        let height = rows.first?.height ?? 64
        return DefaultSectionContent(cells: rows.map(AnyCellPresenter.init)) { _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
            let item = NSCollectionLayoutItem(layoutSize: size)
            item.contentInsets = .init(top: 0, leading: 0, bottom: 5, trailing: 0)
            return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [item]))
        }
    }
}

private struct Anchor {
    let id: AnyHashable
    let distanceFromTop: CGFloat
}

private struct Measurement: Codable {
    let backend: String
    let scenario: String
    let compensated: Bool
    let anchor: String
    let beforeY: Double
    let afterY: Double?
    let beforeOffset: Double
    let afterOffset: Double
    let largestObservedPresentationDrift: Double
    let sampledFrames: Int
}

@MainActor
private final class Lane: UIView {
    let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
    let owner: CollectionOrchestrator
    let compensated: Bool
    let heading: UILabel
    let metric = label("更新前", size: 12, weight: .medium)
    let guide = UIView()
    let lead = Section("lead", rows: [Row(id: 900, height: 192)])
    let feed = Section("feed", rows: (1...60).map { Row(id: $0) })
    var watched: Anchor?
    var baselineOffset: CGFloat = 0
    var maxDrift: CGFloat = 0
    var sampledFrames = 0
    var displayLink: CADisplayLink?

    init(compensated: Bool, native: Bool) {
        self.compensated = compensated
        heading = label(compensated ? "实验：更新完成后按内容补偿" : "对照：Parade 当前默认更新", size: 14, weight: .bold)
        if native {
            owner = CollectionOrchestrator(collectionView: collection) { view, cell, supplementary in
                DiffableCollectionDataSource(collectionView: view, cellProvider: cell, supplementaryProvider: supplementary)
            }
        } else {
            owner = CollectionOrchestrator(collectionView: collection)
        }
        super.init(frame: .zero)
        backgroundColor = .white
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 0.88, alpha: 1).cgColor
        collection.backgroundColor = .white
        collection.contentInsetAdjustmentBehavior = .never
        collection.showsVerticalScrollIndicator = false
        for child in [heading, metric, collection, guide] { addSubview(child) }
        guide.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.8)
        guide.isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        heading.frame = CGRect(x: 14, y: 10, width: bounds.width - 28, height: 22)
        metric.frame = CGRect(x: 14, y: 34, width: bounds.width - 28, height: 18)
        collection.frame = CGRect(x: 14, y: 62, width: bounds.width - 28, height: bounds.height - 74)
        guide.frame = CGRect(x: 8, y: 62 + 28, width: bounds.width - 16, height: 1)
    }
    func prepare() async throws {
        lead.rows = [Row(id: 900, height: 192)]
        feed.rows = (1...60).map { Row(id: $0) }
        try await owner.compose([lead, feed]).updating([lead, feed]).apply(animated: false, mode: .reload)
        collection.layoutIfNeeded()
        if let path = owner.indexPath(for: 21), let attributes = collection.layoutAttributesForItem(at: path) {
            collection.setContentOffset(CGPoint(x: 0, y: attributes.frame.minY - 28), animated: false)
            collection.layoutIfNeeded()
        }
        metric.text = "第 21 条距列表顶端 28 pt · 橙线是参考位置"
        metric.textColor = .secondaryLabel
    }
    func captureAnchor() -> Anchor? {
        let top = collection.contentOffset.y + collection.adjustedContentInset.top
        let visible = collection.indexPathsForVisibleItems.compactMap { path -> (IndexPath, CGRect)? in
            guard let frame = collection.layoutAttributesForItem(at: path)?.frame, frame.minY >= top else { return nil }
            return (path, frame)
        }.sorted { $0.1.minY < $1.1.minY }
        guard let (path, frame) = visible.first, let presenter = owner.cellPresenter(at: path) else { return nil }
        return Anchor(id: presenter.id, distanceFromTop: frame.minY - top)
    }
    func position(of anchor: Anchor) -> CGFloat? {
        guard let path = owner.indexPath(for: anchor.id), let attributes = collection.layoutAttributesForItem(at: path) else { return nil }
        return attributes.frame.minY - collection.contentOffset.y - collection.adjustedContentInset.top
    }
    func restore(_ anchor: Anchor) {
        guard let path = owner.indexPath(for: anchor.id), let attributes = collection.layoutAttributesForItem(at: path) else { return }
        let desired = attributes.frame.minY - anchor.distanceFromTop - collection.adjustedContentInset.top
        let minimum = -collection.adjustedContentInset.top
        let maximum = max(minimum, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom)
        collection.setContentOffset(CGPoint(x: collection.contentOffset.x, y: min(maximum, max(minimum, desired))), animated: false)
        collection.layoutIfNeeded()
    }
    func startSampling() {
        watched = captureAnchor()
        baselineOffset = collection.contentOffset.y
        maxDrift = 0
        sampledFrames = 0
        displayLink = CADisplayLink(target: self, selector: #selector(sample))
        displayLink?.add(to: .main, forMode: .common)
    }
    @objc private func sample() {
        guard let watched, let path = owner.indexPath(for: watched.id),
              let cell = collection.cellForItem(at: path), cell.accessibilityIdentifier == String(describing: watched.id),
              let layer = cell.layer.presentation(), let scrollLayer = collection.layer.presentation() else { return }
        let y = layer.frame.minY - scrollLayer.bounds.minY - collection.adjustedContentInset.top
        maxDrift = max(maxDrift, abs(y - watched.distanceFromTop))
        sampledFrames += 1
    }
    func mutate(_ scenario: Int) async throws {
        switch scenario {
        case 0, 3: feed.rows.insert(contentsOf: [Row(id: -1), Row(id: -2)], at: 0)
        case 1: lead.rows = [Row(id: 900, height: 352)]
        default: break
        }
        let sections: [any SectionController] = scenario == 2 ? [feed, lead] : [lead, feed]
        try await owner.compose(sections).updating([lead, feed]).apply(animated: scenario == 3)
        if compensated, let watched { restore(watched) }
    }
    func finish(backend: String, scenario: String) -> Measurement? {
        displayLink?.invalidate()
        displayLink = nil
        guard let watched else { metric.text = "没有可用锚点"; return nil }
        let after = position(of: watched)
        let drift = after.map { $0 - watched.distanceFromTop }
        metric.text = drift.map { String(format: "最终偏移 %+.0f pt   ·   offset %.0f → %.0f", $0, baselineOffset, collection.contentOffset.y) } ?? "锚点已被删除"
        metric.textColor = abs(drift ?? 0) < 0.5 ? .systemGreen : .systemRed
        return Measurement(backend: backend, scenario: scenario, compensated: compensated,
                           anchor: String(describing: watched.id), beforeY: Double(watched.distanceFromTop),
                           afterY: after.map(Double.init), beforeOffset: Double(baselineOffset),
                           afterOffset: Double(collection.contentOffset.y),
                           largestObservedPresentationDrift: Double(maxDrift), sampledFrames: sampledFrames)
    }
}

@MainActor
private final class DemoController: UIViewController {
    private let native = ProcessInfo.processInfo.arguments.contains("--native")
    private lazy var baseline = Lane(compensated: false, native: native)
    private lazy var anchored = Lane(compensated: true, native: native)
    private let titleLabel = label("保住正在读的这一条", size: 27, weight: .bold)
    private let subtitle = label("真实 UIKit 对照 · 看蓝色卡片与橙线的关系", size: 12, color: .secondaryLabel)
    private let sceneLabel = label("准备演示", size: 18, weight: .semibold)
    private let note = label("", size: 13)
    private let button = UIButton(type: .system)
    private var running = false
    private let titles = ["1 / 4   上方插入两条内容", "2 / 4   上方模块增加 160 pt", "3 / 4   上方模块移到列表尾部", "4 / 4   插入内容，同时开启动画"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)
        for child in [titleLabel, subtitle, sceneLabel, baseline, anchored, note, button] { view.addSubview(child) }
        button.setTitle("播放四个场景", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.addAction(UIAction { [weak self] _ in self?.play() }, for: .touchUpInside)
        subtitle.text = "真实 UIKit · \(native ? "Apple Diffable" : "Parade 默认数据源") · 实验补偿"
        note.text = "不是固定 contentOffset 数字，而是保住同一条内容的屏幕位置。"
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top + 10
        let width = view.bounds.width - 32
        titleLabel.frame = CGRect(x: 16, y: top, width: width, height: 36)
        subtitle.frame = CGRect(x: 16, y: top + 40, width: width, height: 22)
        sceneLabel.frame = CGRect(x: 16, y: top + 76, width: width, height: 27)
        let panelTop = top + 115
        let bottom = view.bounds.height - view.safeAreaInsets.bottom
        let height = (bottom - panelTop - 104) / 2
        baseline.frame = CGRect(x: 16, y: panelTop, width: width, height: height)
        anchored.frame = CGRect(x: 16, y: panelTop + height + 12, width: width, height: height)
        note.frame = CGRect(x: 18, y: bottom - 82, width: width - 4, height: 48)
        button.frame = CGRect(x: 16, y: bottom - 32, width: width, height: 30)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if ProcessInfo.processInfo.arguments.contains("--autoplay") { play() }
    }
    private func play() {
        guard !running else { return }
        running = true
        button.isEnabled = false
        Task { @MainActor in
            do {
                var results: [Measurement] = []
                for scenario in 0...3 {
                    sceneLabel.text = titles[scenario]
                    note.text = "更新前：两边都在读第 21 条。\n橙线标记它在列表中的原始位置。"
                    try await baseline.prepare()
                    try await anchored.prepare()
                    try await Task.sleep(for: .seconds(2.5))
                    baseline.startSampling()
                    anchored.startSampling()
                    note.text = "更新后：同一组数据，同一个布局。\n比较蓝色卡片有没有离开橙色参考线。"
                    let first = Task { try await baseline.mutate(scenario) }
                    let second = Task { try await anchored.mutate(scenario) }
                    try await first.value
                    try await second.value
                    try await Task.sleep(for: .milliseconds(350))
                    let backend = native ? "diffable" : "default"
                    if let result = baseline.finish(backend: backend, scenario: titles[scenario]) {
                        results.append(result)
                        if let afterY = result.afterY, abs(afterY - result.beforeY) < 0.5 {
                            note.text = "这个场景里 UIKit 已自行保住位置。\n实验方案不应再重复添加偏移量。"
                        } else {
                            note.text = "上方：阅读位置改变。下方：回到参考线。\n保持的是同一条内容，不是 offset 数字。"
                        }
                    }
                    if let result = anchored.finish(backend: backend, scenario: titles[scenario]) { results.append(result) }
                    try await Task.sleep(for: .seconds(3))
                }
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(results).write(to: directory.appendingPathComponent("measurements.json"), options: .atomic)
                sceneLabel.text = "演示完成 · 系统行为因场景而异"
                note.text = "已保存逐场景坐标与动画采样。\n这是研究原型，还不是 Parade 的正式能力。"
            } catch {
                note.text = "演示失败：\(error)"
            }
            running = false
            button.isEnabled = true
            button.setTitle("重新播放", for: .normal)
        }
    }
}
