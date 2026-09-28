#!/usr/bin/env python3
# Created by weixi on 2026/10/02.
"""Generate an isolated typed-layout experiment from the current Parade sources."""

import hashlib
import json
import pathlib
import re
import shutil

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
WORK = ROOT / '.build' / 'LayoutCompositionStudy'
PACKAGE = WORK / 'Package'


def replace(text, old, new):
    assert old in text, old
    return text.replace(old, new)


def prepare():
    destination = PACKAGE / 'Sources' / 'Parade'
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(ROOT / 'Sources' / 'Parade', destination)
    generic = [
        'SectionSnapshot', 'CollectionSnapshot', 'CollectionContentUpdates',
        'CollectionBatch', 'CollectionUpdatePlan', 'CollectionOrchestrator',
        'CollectionUpdate', 'DefaultCollectionDataSource', 'DiffableCollectionDataSource',
        'CollectionViewBridge', 'SectionLayoutSnapshot', 'SectionStore', 'SectionDefinition',
        'CollectionDataSource', 'SectionController', 'StoredSection',
    ]
    pattern = r'\b(' + '|'.join(generic) + r')\b'
    for path in destination.rglob('*.swift'):
        text = re.sub(pattern, r'\1<Layout>', path.read_text())
        text = re.sub(r'(extension \w+)<Layout>', r'\1', text)
        if path.name in ['CollectionDisplayObserving.swift', 'SectionDisplayObserving.swift', 'SectionAttachmentObserving.swift']:
            text = text.replace(': SectionController<Layout>', ': SectionController')
        if path.name == 'SectionStore.swift':
            # Swift 6.4 crashes lowering a constrained existential key path.
            text = text.replace('map(\\.controller)', 'map { $0.controller }')
        if path.name == 'CollectionUpdatePlan+Validation.swift':
            text = text.replace('func sameIdentities(', 'func sameIdentities<Layout>(')
            text = text.replace('func contains(', 'func contains<Layout>(')
            text = text.replace('if !condition { throw CollectionUpdatePlan<Layout>.ValidationError(message) }',
                                'if !condition { throw CollectionUpdatePlan<Never>.ValidationError(message) }')
        path.write_text(text)

    path = destination / 'Section/SectionController.swift'
    text = path.read_text().replace('associatedtype Content: SectionContent',
        'associatedtype Layout\n    associatedtype Content: SectionContent where Content.Layout == Layout')
    path.write_text(text)

    path = destination / 'Section/SectionSnapshot.swift'
    text = path.read_text()
    start = text.index('    /// Resolves the layout')
    end = text.index('    public var items:', start)
    text = text[:start] + '    public var layoutValue: Layout { layout.value }\n\n' + text[end:]
    text = text.replace('layout = SectionLayoutSnapshot<Layout>(content)',
                        'layout = SectionLayoutSnapshot<Layout>(content.layout)')
    text = text.replace('layout: @escaping @MainActor (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection',
                        'layout: Layout')
    text = text.replace('SectionLayoutSnapshot<Layout>(makeLayout: layout)', 'SectionLayoutSnapshot<Layout>(layout)')
    path.write_text(text)

    path = destination / 'DataSource/CollectionDataSource.swift'
    text = path.read_text().replace('public protocol CollectionDataSource<Layout>: AnyObject {',
        'public protocol CollectionDataSource<Layout>: AnyObject {\n    associatedtype Layout')
    start = text.index('    /// Uses the same captured version')
    end = text.index('    /// Queries describe', start)
    text = text[:start] + '    func sectionSnapshot(at index: Int) -> SectionSnapshot<Layout>?\n\n' + text[end:]
    path.write_text(text)
    for relative, body in [
        ('DataSource/Default/DefaultCollectionDataSource.swift', 'section(at: index)'),
        ('DataSource/DiffableCollectionDataSource.swift',
         'guard let id = sectionId(at: index) else { return nil }\n        return current.sectionsById[id] ?? previous.sectionsById[id]'),
    ]:
        path = destination / relative
        text = path.read_text()
        start = text.index('    public func layoutSection(')
        end = text.index('    public func cellPresenter', start)
        text = text[:start] + '    public func sectionSnapshot(at index: Int) -> SectionSnapshot<Layout>? {\n        ' + body + '\n    }\n\n' + text[end:]
        # Primary-associated-type constraints belong on use sites, not conformances.
        text = text.replace(': NSObject, CollectionDataSource<Layout>,', ': NSObject, CollectionDataSource,')
        text = text.replace(': CollectionDataSource<Layout> {', ': CollectionDataSource {')
        path.write_text(text)

    path = destination / 'CollectionOrchestrator.swift'
    text = path.read_text()
    start = text.index('    /// Uses Parade')
    end = text.index('    /// Creates one data-source', start)
    text = text[:start] + '''    public convenience init(
        collectionView: UICollectionView,
        layout: CollectionLayout<Layout>,
        diffAlgorithm: any SectionedDiffAlgorithm = SectionedDiff()
    ) {
        self.init(collectionView: collectionView, layout: layout) { view, cell, supplementary in
            DefaultCollectionDataSource<Layout>(collectionView: view, cellProvider: cell,
                supplementaryProvider: supplementary, diffAlgorithm: diffAlgorithm)
        }
    }

''' + text[end:]
    text = text.replace('configuration: UICollectionViewCompositionalLayoutConfiguration? = nil,',
                        'layout: CollectionLayout<Layout>,')
    text = text.replace('let bridge = CollectionViewBridge<Layout>(collectionView: collectionView)',
                        'let access = LayoutAccess<Layout>()\n        let bridge = layout.makeDelegate(collectionView, access)')
    text = text.replace('bridge.owner = self', 'bridge.owner = self\n        access.owner = self')
    start = text.index('        collectionView.setCollectionViewLayout(UICollectionViewCompositionalLayout(')
    end = text.index('        Task {', start)
    text = text[:start] + '        collectionView.setCollectionViewLayout(layout.makeLayout(access), animated: false)\n' + text[end:]
    text = text.replace('    private let source: any CollectionDataSource<Layout>',
                        '    let source: any CollectionDataSource<Layout>')
    path.write_text(text)

    path = destination / 'UIKit/CollectionViewBridge.swift'
    text = path.read_text().replace('final class CollectionViewBridge<Layout>', 'open class CollectionViewBridge<Layout>')
    text = text.replace('    init(collectionView:', '    public init(collectionView:')
    text = re.sub(r'(?m)^    func (collectionView|scrollView\w*)\(', r'    public func \1(', text)
    text = text.replace('    func viewForZooming(', '    public func viewForZooming(')
    text = text.replace('private static let emptyViewReuseIdentifier = "Parade.CollectionViewBridge<Layout>.empty"',
                        'private static var emptyViewReuseIdentifier: String { "Parade.CollectionViewBridge.empty" }')
    # Objective-C delegate witnesses must live in the body of a generic class.
    text = re.sub(r'\n}\n(\n//[^\n]*\n)*\nextension CollectionViewBridge \{', '\n', text)
    text = re.sub(r'\n}\n(\n//[^\n]*\n)*\nprivate extension CollectionViewBridge \{', '\n', text)
    path.write_text(text)

    path = destination / 'Section/Store/SectionDefinition.swift'
    text = path.read_text().replace('protocol StoredSection<Layout>: AnyObject {',
        'protocol StoredSection<Layout>: AnyObject {\n    associatedtype Layout')
    text = text.replace('SectionInstance<Input, Controller>', 'SectionInstance<Layout, Input, Controller>')
    text = text.replace('SectionInstance<Input, Controller: SectionController<Layout>>: StoredSection<Layout>',
        'SectionInstance<Layout, Input, Controller: SectionController<Layout>>: StoredSection')
    path.write_text(text)

    for overlay in (HERE / 'Overlay').glob('*.swift'):
        target = destination / ('Section/SectionContent.swift' if overlay.name == 'SectionContent.swift' else overlay.name)
        shutil.copy2(overlay, target)
    # A separate consumer module proves the experiment does not rely on @testable access.
    for folder, target in [('Support', PACKAGE / 'Sources/StudySupport'), ('Tests', PACKAGE / 'Tests/StudyTests')]:
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(HERE / folder, target)
    (PACKAGE / 'Package.swift').write_text('''// swift-tools-version: 6.0
// Created by weixi on 2026/10/02.
import PackageDescription
let package = Package(name: "LayoutCompositionStudy", platforms: [.iOS(.v16)],
    products: [.library(name: "Parade", targets: ["Parade"]), .library(name: "StudySupport", targets: ["StudySupport"])],
    targets: [.target(name: "Parade"), .target(name: "StudySupport", dependencies: ["Parade"]),
              .testTarget(name: "StudyTests", dependencies: ["Parade", "StudySupport"])],
    swiftLanguageModes: [.v6])
''')
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((ROOT / 'Sources/Parade').rglob('*.swift'))}
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / 'source-manifest.json').write_text(json.dumps(hashes, indent=2) + '\n')
    print(PACKAGE)


if __name__ == '__main__':
    prepare()
