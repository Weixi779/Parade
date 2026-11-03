// Created by weixi on 2026/09/17.
import UIKit

enum UIEngine: String, CaseIterable {
    case apple = "Apple-diff-reconfigure"
    case differenceKit = "DifferenceKit-staged"
    case lisBefore = "LIS-before-reload"
    case lisAfter = "LIS-after-reload"
    case lisReconfigure = "LIS-after-reconfigure"
    case reload = "UIKit-reloadData"
    case appleReload = "Apple-reloadData"
    case lisThenReload = "LIS-then-reloadData"
    var native: Bool { self == .apple || self == .appleReload }
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
        if engine.native {
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

    func applyStage(_ stage: Changeset<[UISection]>, reconfigure: Bool = false) async {
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
                    let updatedPaths = stage.elementUpdated.map { IndexPath(item: $0.element, section: $0.section) }
                    if reconfigure { self.collection.reconfigureItems(at: updatedPaths) }
                    else { self.collection.reloadItems(at: updatedPaths) }
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
        let prepared: UInt64
        var planned: [SectionStage] = []
        if let native {
            let targetItems = fixture.new.flatMap(\.elements)
            let changed = engine == .apple ? targetItems.filter { item in
                items[item.id].map { $0.revision != item.revision } ?? false
            }.map(\.id) : []
            items = Dictionary(uniqueKeysWithValues: targetItems.map { ($0.id, $0) })
            var target = snapshot(fixture.new)
            if !changed.isEmpty { target.reconfigureItems(changed) }
            prepared = nanos()
            await withCheckedContinuation { (c: CheckedContinuation<Void,Never>) in
                if engine == .appleReload { native.applySnapshotUsingReloadData(target) { c.resume() } }
                else { native.apply(target, animatingDifferences: false) { c.resume() } }
            }
            sections = fixture.new
        } else if engine == .reload || engine == .lisThenReload {
            if engine == .lisThenReload { planned = sectionPlan(fixture.old,fixture.new,content:.after) }
            prepared = nanos()
            sections = fixture.new
            collection.reloadData()
        } else {
            if engine == .differenceKit {
                planned = StagedChangeset(source:fixture.old,target:fixture.new).map { SectionStage(name:"DifferenceKit",changes:$0) }
            } else {
                planned = sectionPlan(fixture.old,fixture.new,content:engine == .lisBefore ? .before : .after)
            }
            prepared = nanos()
            for stage in planned {
                await applyStage(stage.changes,reconfigure:engine == .lisReconfigure && stage.contentOnly)
            }
        }
        let completed = nanos()
        collection.layoutIfNeeded()
        let layoutDone = nanos()
        let record: [String: Any] = ["prepareMs":Double(prepared-start)/1e6,
            "applyMs":Double(completed-prepared)/1e6,"layoutMs":Double(layoutDone-completed)/1e6,
            "totalMs":Double(layoutDone-start)/1e6,"counts":operationCounts(planned),
            "countsObservable":!engine.native,"configuredCells":configured,
            "plannedButDiscarded":engine == .lisThenReload]
        verify(fixture.new)
        return record
    }

    func verify(_ expected: [UISection]) {
        precondition(collection.window != nil)
        if expected.contains(where: { !$0.elements.isEmpty }) { precondition(!collection.visibleCells.isEmpty) }
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

@MainActor final class RunnerController: UIViewController {
    var started = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }; started = true
        Task { await run() }
    }
    func run() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
        let arguments = ProcessInfo.processInfo.arguments
        let suite = arguments.firstIndex(of:"--suite").flatMap { $0+1 < arguments.count ? arguments[$0+1] : nil } ?? "all"
        var all: [UIFixture] = []
        if suite == "all" || suite == "matrix" { all += [2,20,1000].flatMap(matrixFixtures) }
        if suite == "all" || suite == "permutation" { all += [1000,10000].flatMap(permutationFixtures) }
        if suite == "all" || suite == "churn" { all += [100,1000,10000].flatMap(churnFixtures) }
        if suite == "all" || suite == "random" { all += randomizedSectionFixtures(200) }
        var output: [[String:Any]] = []
        var rng = BenchRNG(state:0x726f756e6432)
        func save(_ finished: Bool) {
            let result: [String:Any] = ["date":ISO8601DateFormatter().string(from:Date()),"complete":finished,
                "suite":suite,"os":UIDevice.current.systemVersion,"simulator":true,"animations":false,
                "device":ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? UIDevice.current.model,
                "records":output,"note":"Completion/call plus layout, not displayed-frame timing. Fixed-size cells. No production fallback threshold."]
            do {
                let url = URL.documentsDirectory.appendingPathComponent("round2-\(suite).json")
                try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)
            } catch { fatalError("\(error)") }
        }
        for fixture in all {
            var engines: [UIEngine]
            switch fixture.group {
            case "churn": engines = [.apple,.differenceKit,.lisReconfigure,.reload,.appleReload,.lisThenReload]
            case "permutation": engines = [.apple,.differenceKit,.lisReconfigure]
            default: engines = [.apple,.differenceKit,.lisBefore,.lisAfter,.lisReconfigure]
            }
            let warmups = fixture.group == "random" ? 0 : 3
            let runs = fixture.group == "random" ? 1 : 12
            var records: [UIEngine:[[String:Any]]] = [:]
            let before = "START \(fixture.group) \(fixture.name) n=\(fixture.count)\n"
            FileHandle.standardOutput.write(Data(before.utf8))
            for iteration in 0..<(warmups+runs) {
                engines.shuffle(using:&rng)
                for engine in engines {
                    if iteration == 0 { FileHandle.standardOutput.write(Data("TRY \(engine.rawValue)\n".utf8)) }
                    let host = UIHost(engine:engine,container:view)
                    await host.reset(fixture.old)
                    let result = await host.apply(fixture)
                    if iteration >= warmups { records[engine,default:[]].append(result) }
                    // Outside timing, exercise each surviving section's first/last
                    // cell, so cross-section targets below the initial viewport
                    // are checked too. This is still not exhaustive visual QA.
                    for (s,section) in fixture.new.enumerated() where !section.elements.isEmpty {
                        for i in Set([0,section.elements.count-1]) {
                            host.collection.scrollToItem(at:IndexPath(item:i,section:s),at:.top,animated:false)
                            host.collection.layoutIfNeeded()
                            host.verify(fixture.new)
                        }
                    }
                    host.collection.removeFromSuperview()
                }
                await Task.yield()
            }
            var minMoveFraction: Double = 0
            var positionChangedFraction: Double = 0
            if fixture.group == "churn" {
                let oldIndex = Dictionary(uniqueKeysWithValues:fixture.old[0].elements.enumerated().map { ($0.element.id,$0.offset) })
                let order=fixture.new[0].elements.map { oldIndex[$0.id]! }
                minMoveFraction=Double(order.count-permutationLISLength(order))/Double(order.count)
                positionChangedFraction=Double(order.enumerated().filter { $0.offset != $0.element }.count)/Double(order.count)
            }
            for engine in engines {
                let samples=records[engine]!
                var record: [String:Any] = ["engine":engine.rawValue,"scenario":fixture.name,"group":fixture.group,
                    "n":fixture.count,"sections":fixture.old.count,"samples":samples,"warmups":warmups,"runs":runs,
                    "counts":samples[0]["counts"]!,"countsObservable":!engine.native,
                    "requestedFraction":fixture.requestedFraction,"minimumMoveFraction":minMoveFraction,
                    "positionChangedFraction":positionChangedFraction,"seed":fixture.seed]
                for key in ["prepareMs","applyMs","layoutMs","totalMs"] {
                    let values=samples.map { $0[key] as! Double }
                    record["median-\(key)"]=percentile(values,0.5)
                    record["p95-\(key)"]=percentile(values,0.95)
                }
                record["median-configuredCells"]=percentile(samples.map { Double($0["configuredCells"] as! Int) },0.5)
                output.append(record)
            }
            // Random smoke cases need no checkpoint per tiny case.
            if fixture.group != "random" || output.count % 50 == 0 { save(false) }
        }
        save(true)
        let message="BENCHMARK_COMPLETE \(suite) \(output.count) comparisons\n"
        FileHandle.standardOutput.write(Data(message.utf8))
        let label=UILabel(frame:view.bounds)
        label.numberOfLines=0; label.textAlignment = .center
        label.text="Parade diff round 2\n\(output.count) comparisons complete\nAll UIKit checks passed"
        view.addSubview(label)
        if arguments.contains("--exit-when-done") { exit(0) }
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
