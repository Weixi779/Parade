// Created by weixi on 2026/09/17.
import UIKit

typealias UIItem = BenchItem<String>
struct UIHeader: Differentiable, Equatable {
    let id: Int
    var differenceIdentifier: Int { id }
}
typealias UISection = ArraySection<UIHeader, UIItem>

enum UIEngine: String, CaseIterable {
    case appleReload = "Apple-reload"
    case appleReconfigure = "Apple-reconfigure"
    case differenceKit = "DifferenceKit-staged"
    case heckel = "Unique-Heckel-staged"
    case lis = "Key-LIS-staged"
    var apple: Bool { self == .appleReload || self == .appleReconfigure }
}

struct UIFixture {
    let name: String
    let old: [UISection]
    let new: [UISection]
    let flat: Bool
    var count: Int { old.reduce(0) { $0 + $1.elements.count } }
}

@MainActor final class BenchCell: UICollectionViewCell {
    let label = UILabel()
    var renderedID = ""
    var renderedRevision = -1
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        contentView.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); label.frame = contentView.bounds.insetBy(dx: 8, dy: 0) }
    func configure(_ item: UIItem) {
        renderedID = item.id; renderedRevision = item.revision
        label.text = "\(item.id) · \(item.revision)"
    }
}

@MainActor final class UIHost: NSObject, UICollectionViewDataSource {
    let collection: UICollectionView
    let engine: UIEngine
    var sections: [UISection] = []
    var items: [String: UIItem] = [:]
    var native: UICollectionViewDiffableDataSource<Int, String>?
    var configured = 0

    init(engine: UIEngine, container: UIView) {
        self.engine = engine
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 36)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collection = UICollectionView(frame: container.bounds, collectionViewLayout: layout)
        super.init()
        collection.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        collection.backgroundColor = .systemBackground
        collection.isPrefetchingEnabled = false
        collection.register(BenchCell.self, forCellWithReuseIdentifier: "cell")
        container.addSubview(collection)
        if engine.apple {
            native = UICollectionViewDiffableDataSource<Int,String>(collectionView: collection) { [weak self] view, path, id in
                let cell = view.dequeueReusableCell(withReuseIdentifier: "cell", for: path) as! BenchCell
                guard let self, let item = self.items[id] else { preconditionFailure("Missing native content") }
                self.configured += 1; cell.configure(item)
                return cell
            }
        } else { collection.dataSource = self }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].elements.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: path) as! BenchCell
        configured += 1; cell.configure(sections[path.section].elements[path.item])
        return cell
    }

    func snapshot(_ values: [UISection]) -> NSDiffableDataSourceSnapshot<Int,String> {
        var result = NSDiffableDataSourceSnapshot<Int,String>()
        for section in values {
            result.appendSections([section.model.id])
            result.appendItems(section.elements.map(\.id), toSection: section.model.id)
        }
        return result
    }

    func reset(_ values: [UISection]) async {
        sections = values
        items = Dictionary(uniqueKeysWithValues: values.flatMap(\.elements).map { ($0.id, $0) })
        if let native {
            let value = snapshot(values)
            await withCheckedContinuation { (c: CheckedContinuation<Void,Never>) in
                native.applySnapshotUsingReloadData(value) { c.resume() }
            }
        } else { collection.reloadData() }
        collection.setContentOffset(.zero, animated: false)
        collection.layoutIfNeeded()
        configured = 0
    }

    func applyStage(_ stage: Changeset<[UISection]>) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void,Never>) in
            UIView.performWithoutAnimation {
                collection.performBatchUpdates {
                    self.sections = stage.data
                    self.collection.deleteSections(IndexSet(stage.sectionDeleted))
                    self.collection.insertSections(IndexSet(stage.sectionInserted))
                    self.collection.reloadSections(IndexSet(stage.sectionUpdated))
                    for move in stage.sectionMoved { self.collection.moveSection(move.source, toSection: move.target) }
                    self.collection.deleteItems(at: stage.elementDeleted.map { IndexPath(item: $0.element, section: $0.section) })
                    self.collection.insertItems(at: stage.elementInserted.map { IndexPath(item: $0.element, section: $0.section) })
                    self.collection.reloadItems(at: stage.elementUpdated.map { IndexPath(item: $0.element, section: $0.section) })
                    for move in stage.elementMoved {
                        self.collection.moveItem(at: IndexPath(item: move.source.element, section: move.source.section),
                                                 to: IndexPath(item: move.target.element, section: move.target.section))
                    }
                } completion: { finished in
                    precondition(finished, "Interrupted benchmark update")
                    c.resume()
                }
            }
        }
    }

    func apply(_ fixture: UIFixture) async -> [String: Any] {
        let start = nanos()
        var stages = 0, operations = -1
        let prepared: UInt64
        if let native {
            let targetItems = fixture.new.flatMap(\.elements)
            let changed = targetItems.filter { item in
                items[item.id].map { $0.revision != item.revision } ?? false
            }.map(\.id)
            items = Dictionary(uniqueKeysWithValues: targetItems.map { ($0.id, $0) })
            var target = snapshot(fixture.new)
            if engine == .appleReconfigure { target.reconfigureItems(changed) }
            else { target.reloadItems(changed) }
            prepared = nanos()
            await withCheckedContinuation { (c: CheckedContinuation<Void,Never>) in
                native.apply(target, animatingDifferences: false) { c.resume() }
            }
            sections = fixture.new
        } else {
            let changes: [Changeset<[UISection]>]
            if engine == .differenceKit {
                // Use the public flat initializer for flat comparisons, sectioned otherwise.
                if fixture.flat {
                    let flat = Array(StagedChangeset(source: fixture.old[0].elements, target: fixture.new[0].elements))
                    changes = flat.map { stage in
                        Changeset(data: [UISection(model: fixture.old[0].model, elements: stage.data)],
                                  elementDeleted: stage.elementDeleted, elementInserted: stage.elementInserted,
                                  elementUpdated: stage.elementUpdated, elementMoved: stage.elementMoved)
                    }
                } else { changes = Array(StagedChangeset(source: fixture.old, target: fixture.new)) }
            } else {
                precondition(fixture.flat)
                let a = fixture.old[0].elements, b = fixture.new[0].elements
                let plan = makePlan(engine == .lis ? .lis : .heckel, a, b)
                changes = customStages(plan, a, b).map { stage in
                    Changeset(data: [UISection(model: fixture.old[0].model, elements: stage.data)],
                              elementDeleted: stage.elementDeleted, elementInserted: stage.elementInserted,
                              elementUpdated: stage.elementUpdated, elementMoved: stage.elementMoved)
                }
            }
            stages = changes.count
            operations = changes.reduce(0) { $0 + $1.changeCount }
            prepared = nanos()
            // Await every stage to make the measured completion boundary explicit.
            // This is a benchmark executor, not DifferenceKit's fire-and-return extension.
            for stage in changes { await applyStage(stage) }
        }
        let completed = nanos()
        collection.layoutIfNeeded()
        let layoutDone = nanos()
        let record: [String: Any] = ["prepareMs":Double(prepared-start)/1e6,
            "applyMs":Double(completed-prepared)/1e6,"layoutMs":Double(layoutDone-completed)/1e6,
            "totalMs":Double(layoutDone-start)/1e6,"stages":stages,"operations":operations,
            "configuredCells":configured]
        verify(fixture.new)
        return record
    }

    func verify(_ expected: [UISection]) {
        precondition(collection.window != nil && !collection.visibleCells.isEmpty)
        precondition(collection.numberOfSections == expected.count)
        for s in expected.indices { precondition(collection.numberOfItems(inSection: s) == expected[s].elements.count) }
        if let native {
            let state = native.snapshot()
            precondition(state.sectionIdentifiers == expected.map { $0.model.id })
            for section in expected { precondition(state.itemIdentifiers(inSection: section.model.id) == section.elements.map(\.id)) }
        }
        for cell in collection.visibleCells {
            let path = collection.indexPath(for: cell)!
            let expectedItem = expected[path.section].elements[path.item]
            let rendered = cell as! BenchCell
            precondition(rendered.renderedID == expectedItem.id && rendered.renderedRevision == expectedItem.revision,
                         "Visible content mismatch \(engine) at \(path): \(rendered.renderedID) vs \(expectedItem.id)")
        }
    }
}

func uiFixtures(_ n: Int) -> [UIFixture] {
    let names = ["no-op","prepend-5pct","rotate-left-1","rotate-right-1","update-5pct","mixed","shuffle"]
    return fixtures(n).filter { names.contains($0.name) }.map(stringFixture).map { f in
        UIFixture(name: f.name, old: [UISection(model: UIHeader(id: 0), elements: f.old)],
                  new: [UISection(model: UIHeader(id: 0), elements: f.new)], flat: true)
    }
}

func sectionFixtures() -> [UIFixture] {
    let old = (0..<10).map { s in
        UISection(model: UIHeader(id: s), elements: (0..<100).map { UIItem(id: "s\(s):item\($0)") })
    }
    var reordered = old; reordered.insert(reordered.removeLast(), at: 0)
    var added = old
    added.insert(UISection(model: UIHeader(id: 20), elements: (0..<100).map { UIItem(id: "s20:item\($0)") }), at: 0)
    var globalMove = old
    let item = globalMove[0].elements.removeFirst()
    globalMove[1].elements.insert(item, at: 0)
    var scopedMove = old
    scopedMove[0].elements.removeFirst()
    scopedMove[1].elements.insert(UIItem(id: "s1:moved-item0"), at: 0)
    return [UIFixture(name: "section-reorder",old:old,new:reordered,flat:false),
            UIFixture(name: "section-insert",old:old,new:added,flat:false),
            UIFixture(name: "cross-section-stable-ID",old:old,new:globalMove,flat:false),
            UIFixture(name: "cross-section-new-prefixed-ID",old:old,new:scopedMove,flat:false)]
}

@MainActor final class RunnerController: UIViewController {
    var started = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }; started = true
        Task { await run() }
    }
    func run() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
        var output: [[String: Any]] = []
        let all = [100,1000,10000].flatMap(uiFixtures) + sectionFixtures()
        var rng = BenchRNG(state: 0x55494b4954)
        for fixture in all {
            var engines = fixture.flat ? UIEngine.allCases : [.appleReload,.appleReconfigure,.differenceKit]
            var records: [UIEngine: [[String:Any]]] = [:]
            // A fresh attached collection per sample prevents state carryover.
            for iteration in 0..<18 {
                engines.shuffle(using: &rng)
                for engine in engines {
                    let host = UIHost(engine: engine, container: view)
                    await host.reset(fixture.old)
                    let result = await host.apply(fixture)
                    if iteration >= 3 { records[engine,default:[]].append(result) }
                    host.collection.removeFromSuperview()
                }
                await Task.yield()
            }
            for engine in engines {
                let samples = records[engine]!
                var record: [String: Any] = ["engine":engine.rawValue,"scenario":fixture.name,
                    "n":fixture.count,"sections":fixture.old.count,"samples":samples,
                    "operations":samples[0]["operations"]!,"stages":samples[0]["stages"]!]
                for key in ["prepareMs","applyMs","layoutMs","totalMs"] {
                    let values = samples.map { $0[key] as! Double }
                    record["median-\(key)"] = percentile(values,0.5)
                    record["p95-\(key)"] = percentile(values,0.95)
                }
                record["median-configuredCells"] = percentile(samples.map { Double($0["configuredCells"] as! Int) },0.5)
                output.append(record)
            }
            print("UI completed \(fixture.name) n=\(fixture.count)")
        }
        let result: [String: Any] = ["date":ISO8601DateFormatter().string(from: Date()),
            "os":UIDevice.current.systemVersion,"device":ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? UIDevice.current.model,
            "simulator":true,"warmups":3,"runs":15,"animations":false,"prefetch":false,
            "note":"Completion plus layout; not rendered-frame timing. Custom engines flat only.","records":output]
        do {
            let url = URL.documentsDirectory.appendingPathComponent("ui.json")
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: url)
            print("BENCHMARK_COMPLETE \(url.path)")
            let label = UILabel(frame: view.bounds)
            label.numberOfLines = 0; label.textAlignment = .center
            label.text = "Parade diff benchmark\n\(output.count) comparisons complete\nAll visible-cell checks passed"
            view.addSubview(label)
        } catch { fatalError("\(error)") }
    }
}

@main @MainActor final class BenchApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Benchmark", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = BenchScene.self
        return configuration
    }
}

@MainActor final class BenchScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = RunnerController()
        self.window = window
        window.makeKeyAndVisible()
    }
}
