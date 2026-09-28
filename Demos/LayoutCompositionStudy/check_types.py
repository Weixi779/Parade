#!/usr/bin/env python3
# Created by weixi on 2026/10/02.
"""Check public consumer type inference and intentional compile failures."""
import json
import platform
import subprocess
from prepare import WORK

sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
prefix = 'import Parade\nimport StudySupport\nimport UIKit\n'
cases = {
    'concrete-section-assembly': (True, '''
@MainActor func assemble(_ view: UICollectionView, log: EventLog) async throws {
    let collection = CollectionOrchestrator(collectionView: view, layout: .flow())
    let cards = FlowCards(cards: [Card(1, height: 80, log: log)], log: log)
    let banner = FlowBanner(log: log)
    try await collection.compose([banner, cards]).updating([cards]).apply()
}
'''),
    'wrong-layout-family': (False, '''
@MainActor func assemble(_ view: UICollectionView, log: EventLog) {
    let collection = CollectionOrchestrator(collectionView: view, layout: .compositional())
    let section = FlowCards(cards: [], log: log)
    _ = collection.compose([section])
}
'''),
    'nonconforming-delegate': (False, '''
@MainActor func badDelegate() {
    _ = FlowSectionLayout { _ in NSObject() }
}
'''),
    'wrong-datasource-family': (False, '''
@MainActor func assemble(_ view: UICollectionView) {
    _ = CollectionOrchestrator(collectionView: view, layout: .flow()) { view, cell, supplementary in
        DiffableCollectionDataSource<CompositionalSectionLayout>(collectionView: view,
            cellProvider: cell, supplementaryProvider: supplementary)
    }
}
'''),
}
results = []
for name, (expected, source) in cases.items():
    path = WORK / f'{name}.swift'
    path.write_text(prefix + source)
    result = subprocess.run(['xcrun', 'swiftc', '-typecheck', '-swift-version', '6', '-sdk', sdk,
        '-target', f'{platform.machine()}-apple-ios16.0-simulator', '-I', str(WORK / 'Modules'),
        '-module-cache-path', str(WORK / 'ModuleCache'), str(path)], text=True, capture_output=True)
    diagnostics = [line for line in result.stderr.splitlines() if 'error:' in line and '^' not in line]
    passed = (result.returncode == 0) == expected
    results.append({'case': name, 'passed': passed, 'expectedToCompile': expected, 'diagnostics': diagnostics})
    print(name, 'PASS' if passed else 'FAIL', '\n'.join(diagnostics))
(WORK / 'typechecks.json').write_text(json.dumps(results, indent=2) + '\n')
assert all(result['passed'] for result in results)
