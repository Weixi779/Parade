#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Isolate empty UIKit API calls without changing any diff, stage or content policy."""
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
ROUND = ROOT.parent.parent
BENCH = ROUND.parent
DK = pathlib.Path(os.environ.get('DIFFERENCEKIT_PATH', BENCH / '.build' / 'DifferenceKit' / 'Sources')).resolve()
BUILD = ROOT / 'build'
APP = BUILD / 'EmptyCallsProbe.app'
APP.mkdir(parents=True, exist_ok=True)
BUNDLE = 'dev.weixi.ParadeDiffEmptyCallsProbe'

def build():
    original = ROUND / 'Sources' / 'UIMain.swift'
    source = original.read_text()
    source = source.replace('    case apple = ', '''    case heckelNoEmpty = "Unique-Heckel-no-empty-calls"
    case differenceKitNoEmpty = "DifferenceKit-no-empty-calls"
    var guardEmptyCalls: Bool { self == .heckelNoEmpty || self == .differenceKitNoEmpty }
    case apple = ''', 1)
    source = source.replace('static let flat: [Self] = [.apple, .appleReconfigure, .differenceKit, .heckel, .lis, .listLIS, .listHeckel, .listReload]',
        'static let flat: [Self] = [.differenceKit, .differenceKitNoEmpty, .heckel, .heckelNoEmpty, .listHeckel]')
    source = source.replace('engine == .differenceKit', '(engine == .differenceKit || engine == .differenceKitNoEmpty)')
    source = source.replace('engine == .heckel ? .heckel : .lis', '(engine == .heckel || engine == .heckelNoEmpty) ? .heckel : .lis')
    for field, statement in [
        ('sectionDeleted','self.collection.deleteSections(IndexSet(stage.sectionDeleted))'),
        ('sectionInserted','self.collection.insertSections(IndexSet(stage.sectionInserted))'),
        ('sectionUpdated','self.collection.reloadSections(IndexSet(stage.sectionUpdated))'),
        ('elementDeleted','self.collection.deleteItems(at: stage.elementDeleted.map { IndexPath(item: $0.element, section: $0.section) })'),
        ('elementInserted','self.collection.insertItems(at: stage.elementInserted.map { IndexPath(item: $0.element, section: $0.section) })'),
        ('elementUpdated','self.collection.reloadItems(at: stage.elementUpdated.map { IndexPath(item: $0.element, section: $0.section) })'),
    ]:
        assert source.count(statement)==1
        source=source.replace(statement, f'if !self.engine.guardEmptyCalls || !stage.{field}.isEmpty {{ {statement} }}')
    generated = BUILD / 'ProbeMain.swift'
    generated.write_text(source)
    sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'], text=True).strip()
    sources=sorted(DK.glob('*.swift'))
    sources += [BENCH/'Sources'/'Core.swift', BENCH/'round2'/'Sources'/'SectionPlanner.swift',
                BENCH/'round2'/'Sources'/'Fixtures.swift', generated]
    modules=ROUND/'build'/'modules'
    command=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-sdk',sdk,
             '-target','arm64-apple-ios17.0-simulator','-module-cache-path',str(ROUND/'build'/'ModuleCache'),
             '-I',str(modules),'-L',str(modules),'-lListKitLIS','-lListKitHeckel']
    subprocess.run(command+[str(p) for p in sources]+['-o',str(APP/'EmptyCallsProbe')],check=True)
    info=plistlib.loads((ROUND/'build'/'ParadeDiffRound3.app'/'Info.plist').read_bytes())
    info.update(CFBundleIdentifier=BUNDLE,CFBundleName='Empty UIKit Calls Probe',CFBundleExecutable='EmptyCallsProbe')
    (APP/'Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign','--force','--sign','-',str(APP)],check=True)
    manifest={'purpose':'Only guard six empty UIKit calls; same diff, stages, content primitive, completion and layout boundary.',
              'originalHarnessSHA256':hashlib.sha256(original.read_bytes()).hexdigest(),
              'generatedHarnessSHA256':hashlib.sha256(generated.read_bytes()).hexdigest(),
              'binarySHA256':hashlib.sha256((APP/'EmptyCallsProbe').read_bytes()).hexdigest(),
              'sourceHashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
              'moduleHashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in modules.glob('*.a')}}
    (ROOT/'environment.json').write_text(json.dumps(manifest,indent=2)+'\n')

def run():
    inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','-j','devices','available']))
    requested=os.environ.get('PARADE_BENCH_UDID')
    candidates=[(runtime,d) for runtime,ds in inventory['devices'].items() for d in ds
                if d['state']=='Booted' and (d['udid']==requested if requested else 'iOS-27' in runtime and 'iPhone' in d['name'])]
    if not candidates:
        raise SystemExit('Boot an iOS 27 iPhone or set PARADE_BENCH_UDID to a booted simulator.')
    selected=candidates[0]
    udid=selected[1]['udid']
    subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True)
    subprocess.run(['xcrun','simctl','install',udid,str(APP)],check=True)
    container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',udid,BUNDLE,'data'],text=True).strip())
    for rep in [1,2,3]:
        name=f'probe-{rep}.json'
        assert not (ROOT/name).exists(), 'Refusing to overwrite results'
        with (ROOT/f'probe-{rep}.log').open('w') as f:
            subprocess.run(['xcrun','simctl','launch','--console','--terminate-running-process',udid,BUNDLE,
                            '--suite','flat','--n','100','--repetition',str(rep),'--output',name],
                           stdout=f,stderr=subprocess.STDOUT,check=True,timeout=180)
        shutil.copy2(container/'Documents'/name,ROOT/name)
        data=json.loads((ROOT/name).read_text())
        assert data['complete'] and len(data['records'])==60
        print(f'Finished probe {rep}: 60 combinations, 2400 formal samples',flush=True)
    (ROOT/'runtime.json').write_text(json.dumps({'device':selected,'inventory':inventory},indent=2)+'\n')

if sys.argv[-1]=='build': build()
elif sys.argv[-1]=='run': run()
else: raise SystemExit('Usage: probe.py build|run')
