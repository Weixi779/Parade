#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Build an isolated benchmark with two ListKit modules; leave reference checkouts untouched."""
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
BENCH = ROOT.parent
UPSTREAM = pathlib.Path(os.environ.get('LISTS_PATH', BENCH / '.build' / 'Lists')).resolve()
DK = pathlib.Path(os.environ.get('DIFFERENCEKIT_PATH', BENCH / '.build' / 'DifferenceKit' / 'Sources')).resolve()
if not list(DK.glob('*.swift')) or not list((UPSTREAM / 'Sources' / 'ListKit').rglob('*.swift')):
    raise SystemExit('Missing DifferenceKit or Lists checkout; see README.md.')
OUT = ROOT / 'build'
APP = OUT / 'ParadeDiffRound3.app'
MODULES = OUT / 'modules'
APP.mkdir(parents=True, exist_ok=True)
MODULES.mkdir(exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
common = ['xcrun', 'swiftc', '-O', '-whole-module-optimization', '-swift-version', '5',
          '-sdk', sdk, '-target', 'arm64-apple-ios17.0-simulator',
          '-module-cache-path', str(OUT / 'ModuleCache')]

# Keep the matcher, snapshots and executor identical. Change only stationary selection.
greedy = '''
  // Research ablation: next-unconsumed-source move selection, unique IDs only.
  private static func researchHeckelMoves(from matched: [(old: Int, new: Int)], oldCount: Int) -> [(from: Int, to: Int)] {
    var consumed = [Bool](repeating: true, count: oldCount)
    for pair in matched { consumed[pair.old] = false }
    var cursor = 0
    var moves = [(from: Int, to: Int)]()
    for pair in matched {
      while cursor < oldCount && consumed[cursor] { cursor += 1 }
      if pair.old != cursor { moves.append((from: pair.old, to: pair.new)) }
      consumed[pair.old] = true
    }
    return moves
  }
'''
manifest = {'upstreamCommit': subprocess.check_output(['git', '-C', str(UPSTREAM), 'rev-parse', 'HEAD'], text=True).strip(),
            'modules': {}, 'flags': common[2:], 'differenceKitCommit': subprocess.check_output(
                ['git', '-C', str(DK.parent), 'rev-parse', 'HEAD'], text=True).strip()}
for module, ablation in [('ListKitLIS', False), ('ListKitHeckel', True)]:
    destination = OUT / 'generated' / module
    destination.mkdir(parents=True, exist_ok=True)
    files = []
    hashes = {}
    for source in sorted((UPSTREAM / 'Sources' / 'ListKit').rglob('*.swift')):
        relative = source.relative_to(UPSTREAM / 'Sources' / 'ListKit')
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        content = source.read_text()
        if ablation and source.name == 'HeckelDiff.swift':
            needle = 'let moves = minimalMoves(from: matched)'
            assert content.count(needle) == 1
            content = content.replace(needle, 'let moves = researchHeckelMoves(from: matched, oldCount: old.count)')
            marker = '  // MARK: Private'
            assert content.count(marker) == 1
            content = content.replace(marker, marker + '\n' + greedy)
        target.write_text(content)
        files.append(str(target))
        hashes[str(relative)] = {'upstream': hashlib.sha256(source.read_bytes()).hexdigest(),
                                 'compiled': hashlib.sha256(target.read_bytes()).hexdigest()}
    shutil.copy2(UPSTREAM / 'LICENSE', destination / 'LICENSE')
    # Static module linking avoids framework loading and uses the same optimization settings.
    library = MODULES / f'lib{module}.a'
    subprocess.run(common + ['-emit-library', '-static', '-emit-module', '-module-name', module,
        '-emit-module-path', str(MODULES / f'{module}.swiftmodule')] + files +
        [str(ROOT / 'Sources' / 'ListKitBridge.swift'), '-o', str(library)], check=True)
    manifest['modules'][module] = hashes

sources = sorted(str(p) for p in DK.glob('*.swift'))
sources += [str(BENCH / 'Sources' / 'Core.swift'),
            str(BENCH / 'round2' / 'Sources' / 'SectionPlanner.swift'),
            str(BENCH / 'round2' / 'Sources' / 'Fixtures.swift'), str(ROOT / 'Sources' / 'UIMain.swift')]
subprocess.run(common + ['-I', str(MODULES), '-L', str(MODULES), '-lListKitLIS', '-lListKitHeckel'] +
               sources + ['-o', str(APP / 'ParadeDiffRound3')], check=True)
with (APP / 'Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'dev.weixi.ParadeDiffRound3', 'CFBundleName': 'Parade Diff Round 3',
        'CFBundleExecutable': 'ParadeDiffRound3', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
        'CFBundleShortVersionString': '1.0', 'MinimumOSVersion': '17.0', 'LSRequiresIPhoneOS': True,
        'UIDeviceFamily': [1, 2], 'UILaunchScreen': {}, 'UIApplicationSceneManifest': {
            'UIApplicationSupportsMultipleScenes': False, 'UISceneConfigurations': {
                'UIWindowSceneSessionRoleApplication': [{'UISceneConfigurationName': 'Benchmark'}]}}}, f)
subprocess.run(['codesign', '--force', '--sign', '-', str(APP)], check=True)
manifest['harnessHashes'] = {os.path.relpath(p, BENCH): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in [pathlib.Path(s) for s in sources] + [ROOT / 'Sources' / 'ListKitBridge.swift', ROOT / 'build.py']}
manifest['binarySHA256'] = hashlib.sha256((APP / 'ParadeDiffRound3').read_bytes()).hexdigest()
manifest['swift'] = subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True).strip()
manifest['xcode'] = subprocess.check_output(['xcodebuild', '-version'], text=True).strip()
manifest['hostOS'] = subprocess.check_output(['sw_vers'], text=True).strip()
cpu = subprocess.run(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True, capture_output=True)
manifest['cpu'] = cpu.stdout.strip() if cpu.returncode == 0 else 'unavailable in build sandbox'
(OUT / 'environment.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(APP)
