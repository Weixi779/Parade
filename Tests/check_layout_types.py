#!/usr/bin/env python3
# Created by weixi on 2026/10/02.
"""Build public consumers and check layout-family errors against the current library."""
import json
import pathlib
import platform
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORK = ROOT / '.build' / 'LayoutAPIChecks'
WORK.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
common = ['xcrun', 'swiftc', '-swift-version', '6', '-sdk', sdk,
          '-target', f'{platform.machine()}-apple-ios16.0-simulator',
          '-module-cache-path', str(WORK / 'ModuleCache'), '-I', str(WORK)]
for module, directory in [('Parade', 'Sources/Parade'), ('ParadeLayoutSupport', 'Tests/LayoutSupport')]:
    subprocess.run(common + ['-parse-as-library', '-emit-module', '-module-name', module,
        '-emit-module-path', str(WORK / f'{module}.swiftmodule')]
        + [str(p) for p in sorted((ROOT / directory).rglob('*.swift'))], check=True)

cases = {
    'concrete-assembly': (None, '''
@MainActor protocol AppSection: SectionController where Layout == FlowSectionLayout {}
extension AppSection {
    var collectionSection: any SectionController<FlowSectionLayout> { self }
}
@MainActor func submit(_ sections: [any AppSection], to owner: CollectionOrchestrator<FlowSectionLayout>) {
    _ = owner.compose(sections.map { $0.collectionSection })
}
@MainActor func assemble(_ view: UICollectionView, log: EventLog) async throws {
    let owner = CollectionOrchestrator(collectionView: view, layout: .flow())
    let cards = FlowCards(cards: [], log: log)
    let banner = FlowBanner(log: log)
    try await owner.compose([banner, cards]).updating([cards]).apply()
    let values = CollectionOrchestrator(collectionView: view)
    try await values.compose([CompositionalCards(cards: [])]).apply()
}
'''),
    'wrong-layout-family': ('cannot convert', '''
@MainActor func invalid(_ view: UICollectionView, log: EventLog) {
    let owner = CollectionOrchestrator(collectionView: view, layout: .compositional())
    _ = owner.compose([FlowCards(cards: [], log: log)])
}
'''),
    'nonconforming-delegate': ('UICollectionViewDelegateFlowLayout', '''
@MainActor func invalid() { _ = FlowSectionLayout { _ in NSObject() } }
'''),
    'wrong-datasource-family': ('CompositionalSectionLayout', '''
@MainActor func invalid(_ view: UICollectionView) {
    _ = CollectionOrchestrator(collectionView: view, layout: .flow()) { view, views in
        DiffableCollectionDataSource<CompositionalSectionLayout>(collectionView: view,
            views: views)
    }
}
'''),
    'reserved-callback': ('overrid', '''
final class InvalidDelegate: CollectionLayoutDelegate {
    override func collectionView(_ view: UICollectionView, didSelectItemAt path: IndexPath) {}
}
'''),
}
results = []
for name, (error, source) in cases.items():
    path = WORK / f'{name}.swift'
    path.write_text('import Parade\nimport ParadeLayoutSupport\nimport UIKit\n' + source)
    result = subprocess.run(common + ['-typecheck', str(path)], capture_output=True, text=True)
    passed = result.returncode == 0 if error is None else result.returncode != 0 and error in result.stderr
    diagnostics = [line for line in result.stderr.splitlines() if 'error:' in line and '^' not in line]
    results.append({'case': name, 'passed': passed, 'expectedToCompile': error is None, 'diagnostics': diagnostics})
    print(name, 'PASS' if passed else 'FAIL', '\n'.join(diagnostics))
(WORK / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
if not all(result['passed'] for result in results):
    raise SystemExit(1)
