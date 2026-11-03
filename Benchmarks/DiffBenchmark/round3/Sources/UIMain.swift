// Created by weixi on 2026/09/17.
import UIKit
import ListKitLIS
import ListKitHeckel

enum Engine: String, CaseIterable {
    case apple = "Apple-reloadItems"
    case appleReconfigure = "Apple-reconfigure"
    case differenceKit = "DifferenceKit-staged"
    case heckel = "Unique-Heckel-staged"
    case lis = "Key-LIS-staged"
    case listLIS = "ListKit-LIS-exact"
    case listHeckel = "ListKit-Heckel-exact"
    case listReload = "ListKit-default-no-animation"
    case appleReloadData = "Apple-reloadData"
    case reloadData = "UIKit-reloadData"
    var appleSource: Bool { self == .apple || self == .appleReconfigure || self == .appleReloadData }
    var listSource: Bool { self == .listLIS || self == .listHeckel || self == .listReload }
    static let flat: [Self] = [.apple, .appleReconfigure, .differenceKit, .heckel, .lis, .listLIS, .listHeckel, .listReload]
    static let sectioned: [Self] = [.apple, .appleReconfigure, .differenceKit, .listLIS, .listHeckel]
    static let churn: [Self] = [.appleReconfigure, .differenceKit, .heckel, .lis, .listLIS, .listHeckel,
                               .listReload, .appleReloadData, .reloadData]
}

@MainActor final class BenchCollection: UICollectionView {
    var batches = 0, itemMoves = 0, itemInserts = 0, itemDeletes = 0
    var itemReloads = 0, itemReconfigures = 0, sectionMoves = 0, sectionInserts = 0, sectionDeletes = 0, reloads = 0
    override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        batches += 1
        super.performBatchUpdates(updates, completion: completion)
    }
    override func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        itemMoves += 1; super.moveItem(at: indexPath, to: newIndexPath)
    }
    override func insertItems(at paths: [IndexPath]) { itemInserts += paths.count; super.insertItems(at: paths) }
    override func deleteItems(at paths: [IndexPath]) { itemDeletes += paths.count; super.deleteItems(at: paths) }
    override func reloadItems(at paths: [IndexPath]) { itemReloads += paths.count; super.reloadItems(at: paths) }
    override func reconfigureItems(at paths: [IndexPath]) { itemReconfigures += paths.count; super.reconfigureItems(at: paths) }
    override func moveSection(_ section: Int, toSection newSection: Int) { sectionMoves += 1; super.moveSection(section, toSection: newSection) }
    override func insertSections(_ sections: IndexSet) { sectionInserts += sections.count; super.insertSections(sections) }
    override func deleteSections(_ sections: IndexSet) { sectionDeletes += sections.count; super.deleteSections(sections) }
    override func reloadData() { reloads += 1; super.reloadData() }
    func resetCounters() {
        batches = 0; itemMoves = 0; itemInserts = 0; itemDeletes = 0; itemReloads = 0; itemReconfigures = 0
        sectionMoves = 0; sectionInserts = 0; sectionDeletes = 0; reloads = 0
    }
    var counts: [String: Int] {
        ["batches": batches, "itemMoves": itemMoves, "itemInserts": itemInserts, "itemDeletes": itemDeletes,
         "itemReloads": itemReloads, "itemReconfigures": itemReconfigures, "sectionMoves": sectionMoves,
         "sectionInserts": sectionInserts, "sectionDeletes": sectionDeletes, "reloadDataCalls": reloads]
    }
}

@MainActor final class BenchCell: UICollectionViewCell {
    let label = UILabel()
    var renderedID = "", renderedRevision = -1
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

@MainActor final class Host: NSObject, UICollectionViewDataSource {
    let collection: BenchCollection
    let engine: Engine
    var sections: [UISection] = [], items: [String: UIItem] = [:]
    var apple: UICollectionViewDiffableDataSource<Int, String>?
    var listLIS: ListKitLIS.ResearchAdapter?
    var listHeckel: ListKitHeckel.ResearchAdapter?
    var configured = 0

    init(engine: Engine, container: UIView) {
        self.engine = engine
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 36)
        layout.minimumLineSpacing = 0; layout.minimumInteritemSpacing = 0
        collection = BenchCollection(frame: container.bounds, collectionViewLayout: layout)
        super.init()
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .systemBackground
        collection.isPrefetchingEnabled = false
        collection.register(BenchCell.self, forCellWithReuseIdentifier: "cell")
        container.addSubview(collection)
        let provider: @MainActor (UICollectionView, IndexPath, String) -> UICollectionViewCell? = { [weak self] view, path, id in
            guard let self, let item = self.items[id] else { preconditionFailure("Missing content: \(id)") }
            let cell = view.dequeueReusableCell(withReuseIdentifier: "cell", for: path) as! BenchCell
            self.configured += 1; cell.configure(item)
            return cell
        }
        if engine.appleSource {
            apple = UICollectionViewDiffableDataSource(collectionView: collection, cellProvider: provider)
        } else if engine == .listHeckel {
            listHeckel = ListKitHeckel.ResearchAdapter(collection: collection, provider: provider)
        } else if engine.listSource {
            listLIS = ListKitLIS.ResearchAdapter(collection: collection, provider: provider)
        } else { collection.dataSource = self }
    }
    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].elements.count }
    func collectionView(_ view: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
        let cell = view.dequeueReusableCell(withReuseIdentifier: "cell", for: path) as! BenchCell
        configured += 1; cell.configure(sections[path.section].elements[path.item]); return cell
    }
    func snapshot(_ values: [UISection]) -> NSDiffableDataSourceSnapshot<Int, String> {
        var value = NSDiffableDataSourceSnapshot<Int, String>()
        for section in values { value.appendSections([section.model.id]); value.appendItems(section.elements.map(\.id), toSection: section.model.id) }
        return value
    }
    func reset(_ values: [UISection]) async {
        sections = values
        items = Dictionary(uniqueKeysWithValues: values.flatMap(\.elements).map { ($0.id, $0) })
        if let apple {
            let value = snapshot(values)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in apple.applySnapshotUsingReloadData(value) { c.resume() } }
        } else if let listLIS {
            listLIS.prepare(sectionIDs: values.map { $0.model.id }, itemIDs: values.map { $0.elements.map(\.id) }, updates: [])
            await listLIS.reset()
        } else if let listHeckel {
            listHeckel.prepare(sectionIDs: values.map { $0.model.id }, itemIDs: values.map { $0.elements.map(\.id) }, updates: [])
            await listHeckel.reset()
        } else { collection.reloadData() }
        collection.setContentOffset(.zero, animated: false)
        collection.layoutIfNeeded()
        configured = 0; collection.resetCounters()
    }
    func applyStage(_ stage: Changeset<[UISection]>) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            collection.performBatchUpdates {
                self.sections = stage.data
                self.collection.deleteSections(IndexSet(stage.sectionDeleted))
                self.collection.insertSections(IndexSet(stage.sectionInserted))
                self.collection.reloadSections(IndexSet(stage.sectionUpdated))
                for m in stage.sectionMoved { self.collection.moveSection(m.source, toSection: m.target) }
                self.collection.deleteItems(at: stage.elementDeleted.map { IndexPath(item: $0.element, section: $0.section) })
                self.collection.insertItems(at: stage.elementInserted.map { IndexPath(item: $0.element, section: $0.section) })
                self.collection.reloadItems(at: stage.elementUpdated.map { IndexPath(item: $0.element, section: $0.section) })
                for m in stage.elementMoved {
                    self.collection.moveItem(at: IndexPath(item: m.source.element, section: m.source.section),
                                             to: IndexPath(item: m.target.element, section: m.target.section))
                }
            } completion: { finished in precondition(finished); c.resume() }
        }
    }
    func apply(_ fixture: UIFixture) async -> [String: Any] {
        let start = nanos()
        let prepared: UInt64
        if engine.appleSource || engine.listSource {
            let targetItems = fixture.new.flatMap(\.elements)
            let changed = engine == .appleReloadData ? [] : targetItems.filter { item in
                items[item.id].map { $0.revision != item.revision } ?? false
            }.map(\.id)
            items = Dictionary(uniqueKeysWithValues: targetItems.map { ($0.id, $0) })
            if let apple {
                var value = snapshot(fixture.new)
                if !changed.isEmpty {
                    if engine == .apple { value.reloadItems(changed) } else { value.reconfigureItems(changed) }
                }
                prepared = nanos()
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    if engine == .appleReloadData { apple.applySnapshotUsingReloadData(value) { c.resume() } }
                    else { apple.apply(value, animatingDifferences: false) { c.resume() } }
                }
            } else {
                let ids = fixture.new.map { $0.model.id }, itemIDs = fixture.new.map { $0.elements.map(\.id) }
                if let listLIS { listLIS.prepare(sectionIDs: ids, itemIDs: itemIDs, updates: changed) }
                if let listHeckel { listHeckel.prepare(sectionIDs: ids, itemIDs: itemIDs, updates: changed) }
                prepared = nanos()
                if let listLIS { await listLIS.apply(exact: engine != .listReload) }
                if let listHeckel { await listHeckel.apply(exact: true) }
            }
            sections = fixture.new
        } else if engine == .reloadData {
            prepared = nanos(); sections = fixture.new; collection.reloadData()
        } else {
            let changes: [Changeset<[UISection]>]
            if engine == .differenceKit && fixture.group == "matrix" {
                changes = Array(StagedChangeset(source: fixture.old, target: fixture.new))
            } else if engine == .differenceKit && fixture.group == "random" {
                changes = Array(StagedChangeset(source: fixture.old, target: fixture.new))
            } else {
                precondition(fixture.old.count == 1 && fixture.new.count == 1)
                let old = fixture.old[0].elements, new = fixture.new[0].elements
                let flat: [Changeset<[UIItem]>]
                if engine == .differenceKit { flat = Array(StagedChangeset(source: old, target: new)) }
                else { flat = customStages(makePlan(engine == .heckel ? .heckel : .lis, old, new), old, new) }
                changes = flat.map { s in Changeset(data: [UISection(model: fixture.old[0].model, elements: s.data)],
                    elementDeleted: s.elementDeleted, elementInserted: s.elementInserted,
                    elementUpdated: s.elementUpdated, elementMoved: s.elementMoved) }
            }
            prepared = nanos()
            for stage in changes { await applyStage(stage) }
        }
        let applied = nanos()
        collection.layoutIfNeeded()
        let end = nanos()
        let result: [String: Any] = ["prepareMs": Double(prepared-start)/1e6, "applyMs": Double(applied-prepared)/1e6,
            "layoutMs": Double(end-applied)/1e6, "totalMs": Double(end-start)/1e6,
            "configuredCells": configured, "calls": collection.counts]
        verify(fixture.new)
        return result
    }
    func verify(_ expected: [UISection]) {
        precondition(collection.window != nil)
        precondition(collection.numberOfSections == expected.count)
        for s in expected.indices { precondition(collection.numberOfItems(inSection: s) == expected[s].elements.count) }
        if expected.contains(where: { !$0.elements.isEmpty }) { precondition(!collection.visibleCells.isEmpty) }
        let ids = expected.map { $0.elements.map(\.id) }, sectionIDs = expected.map { $0.model.id }
        if let apple {
            let state = apple.snapshot()
            precondition(state.sectionIdentifiers == sectionIDs)
            precondition(state.sectionIdentifiers.map { state.itemIdentifiers(inSection: $0) } == ids)
        }
        if let listLIS { precondition(listLIS.snapshotSections() == sectionIDs && listLIS.snapshotIDs() == ids) }
        if let listHeckel { precondition(listHeckel.snapshotSections() == sectionIDs && listHeckel.snapshotIDs() == ids) }
        for cell in collection.visibleCells {
            let path = collection.indexPath(for: cell)!, rendered = cell as! BenchCell
            let item = expected[path.section].elements[path.item]
            precondition(rendered.renderedID == item.id && rendered.renderedRevision == item.revision,
                         "Content mismatch \(engine.rawValue) \(path): \(rendered.renderedID) / \(item.id)")
        }
    }
}

@MainActor func verifyMatchers() -> Int {
    var count = 0
    func check(_ a: [Int], _ b: [Int]) {
        let old = a.map { BenchItem(id: $0) }, new = b.map { BenchItem(id: $0) }
        for (name, r) in [("LIS", ListKitLIS.ResearchAdapter.flatDiff(a, b)),
                          ("Heckel", ListKitHeckel.ResearchAdapter.flatDiff(a, b))] {
            let p = BenchPlan(deletes: r.deletes, inserts: r.inserts, moves: r.moves.map { BenchMove(from: $0[0], to: $0[1]) })
            validate(p, old, new)
            if name == "LIS" { precondition(p.moves.count == Set(a).intersection(b).count - lcsOracle(a, b)) }
            else { precondition(p.moves.count == keyedPlan(old, new, lis: false).moves.count) }
            count += 1
        }
    }
    func permutations(_ remaining: [Int], _ prefix: [Int], _ original: [Int]) {
        if remaining.isEmpty { check(original, prefix); return }
        for i in remaining.indices { var rest = remaining; let v = rest.remove(at: i); permutations(rest, prefix + [v], original) }
    }
    for n in 0...7 { permutations(Array(0..<n), [], Array(0..<n)) }
    var rng = BenchRNG(state: 0x726f756e6433)
    for _ in 0..<1500 {
        let values = Array(0..<Int(rng.next()%35))
        var a = values.filter { _ in rng.next()%4 != 0 }, b = values.filter { _ in rng.next()%4 != 0 }
        a.shuffle(using: &rng); b.shuffle(using: &rng); check(a, b)
    }
    return count
}

@MainActor final class RunnerController: UIViewController {
    var started = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }; started = true
        Task { await run() }
    }
    func run() async {
        let args = ProcessInfo.processInfo.arguments
        func option(_ key: String, _ fallback: String) -> String {
            guard let i = args.firstIndex(of: key), i+1 < args.count else { return fallback }; return args[i+1]
        }
        let suite = option("--suite", "flat"), repetition = Int(option("--repetition", "1"))!
        let only = option("--scenario", ""), onlyEngine = option("--engine", "")
        let onlyN = Int(option("--n", "0"))!
        let filename = option("--output", "round3-\(suite)-\(repetition).json")
        UIView.setAnimationsEnabled(false)
        precondition(!UIView.areAnimationsEnabled)
        var all: [UIFixture] = []
        switch suite {
        case "flat":
            all = [100,1000,10000].flatMap { n in fixtures(n).map(stringFixture).map { f in
                UIFixture(name: f.name, old: [UISection(model: UIHeader(id: 0), elements: f.old)],
                          new: [UISection(model: UIHeader(id: 0), elements: f.new)], group: "flat")
            } }
        case "permutation": all = [100,1000,10000].flatMap(permutationFixtures)
        case "churn": all = [100,1000,10000].flatMap(churnFixtures)
        case "matrix": all = [2,33,333,3333].flatMap(matrixFixtures)
        case "random": all = randomizedSectionFixtures(200)
        case "verify": break
        default: fatalError("Unknown suite")
        }
        if !only.isEmpty { all = all.filter { $0.name == only } }
        if onlyN != 0 { all = all.filter { $0.count == onlyN } }
        let verified = suite == "verify" ? verifyMatchers() : 0
        var output: [[String: Any]] = []
        var rng = BenchRNG(state: 0x726f756e6433 ^ (UInt64(repetition) &* 0x9e3779b97f4a7c15))
        all.shuffle(using: &rng)
        func save(_ complete: Bool) {
            let data: [String: Any] = ["complete": complete, "suite": suite, "repetition": repetition,
                "date": ISO8601DateFormatter().string(from: Date()), "os": UIDevice.current.systemVersion,
                "device": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown",
                "simulator": true, "uiAnimationsEnabled": UIView.areAnimationsEnabled,
                "listKitExactAnimatingDifferencesParameter": true, "prefetch": false,
                "verifiedMatcherCases": verified, "records": output,
                "note": "Elapsed completion/call plus layout, not displayed-frame time. ListKit/Apple apply includes internal diff; external prepare is snapshot/content adapter only. UIKit counters are instrumented for all candidates."]
            let url = URL.documentsDirectory.appendingPathComponent(filename)
            try! JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted,.sortedKeys]).write(to: url, options: .atomic)
        }
        save(false)
        for fixture in all {
            var engines = fixture.group == "churn" ? Engine.churn :
                (fixture.group == "matrix" || fixture.group == "random" ? Engine.sectioned : Engine.flat)
            if !onlyEngine.isEmpty { engines = engines.filter { $0.rawValue == onlyEngine } }
            let warmups = suite == "random" ? 0 : 5
            let runs = suite == "random" ? 1 : (suite == "flat" ? 40 : 30)
            var records: [Engine: [[String: Any]]] = [:]
            for iteration in 0..<(warmups+runs) {
                engines.shuffle(using: &rng)
                for engine in engines {
                    if iteration == 0 {
                        FileHandle.standardOutput.write(Data("TRY \(suite) \(fixture.name) n=\(fixture.count) \(engine.rawValue)\n".utf8))
                    }
                    let host = Host(engine: engine, container: view)
                    await host.reset(fixture.old)
                    let sample = await host.apply(fixture)
                    if iteration >= warmups { records[engine,default: []].append(sample) }
                    if fixture.group == "matrix" || fixture.group == "random" {
                        for (s,section) in fixture.new.enumerated() where !section.elements.isEmpty {
                            for i in [0,section.elements.count-1] {
                                host.collection.scrollToItem(at: IndexPath(item: i, section: s), at: .top, animated: false)
                                host.collection.layoutIfNeeded(); host.verify(fixture.new)
                            }
                        }
                    }
                    host.collection.removeFromSuperview()
                }
                await Task.yield()
            }
            for engine in engines {
                let samples = records[engine]!
                var row: [String: Any] = ["engine": engine.rawValue, "scenario": fixture.name, "group": fixture.group,
                    "n": fixture.count, "targetN": fixture.new.reduce(0) { $0 + $1.elements.count },
                    "sections": fixture.old.count, "warmups": warmups, "runs": runs, "samples": samples,
                    "requestedFraction": fixture.requestedFraction, "seed": fixture.seed,
                    "callsObservable": !engine.appleSource, "calls": samples[0]["calls"]!]
                for key in ["prepareMs", "applyMs", "layoutMs", "totalMs"] {
                    let values = samples.map { $0[key] as! Double }.sorted()
                    row["median-\(key)"] = values.count % 2 == 0 ? (values[values.count/2-1]+values[values.count/2])/2 : values[values.count/2]
                    row["p95-\(key)"] = percentile(values, 0.95)
                }
                row["median-configuredCells"] = percentile(samples.map { Double($0["configuredCells"] as! Int) }, 0.5)
                output.append(row)
            }
            save(false)
        }
        save(true)
        FileHandle.standardOutput.write(Data("BENCHMARK_COMPLETE \(suite) \(output.count) rows; matcher cases \(verified)\n".utf8))
        exit(0)
    }
}

@main @MainActor final class BenchApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Benchmark", sessionRole: session.role)
        config.delegateClass = BenchScene.self; return config
    }
}
@MainActor final class BenchScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = RunnerController(); self.window = window; window.makeKeyAndVisible()
    }
}
