#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Build the benchmark executables without a Parade package target or upstream edits."""
import os, pathlib, plistlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent
DK = pathlib.Path(os.environ.get('DIFFERENCEKIT_PATH', ROOT / '.build' / 'DifferenceKit' / 'Sources')).resolve()
OUT = ROOT / 'build'
OUT.mkdir(exist_ok=True)
if not DK.is_dir():
    raise SystemExit(f'DifferenceKit sources not found at {DK}. Clone the pinned commit and set DIFFERENCEKIT_PATH; see README.md.')
dk_sources = sorted(str(p) for p in DK.glob('*.swift'))
if not dk_sources:
    raise SystemExit(f'No DifferenceKit sources found under {DK}.')
try:
    commit = subprocess.check_output(['git', '-C', str(DK.parent), 'rev-parse', 'HEAD'], text=True).strip()
    print(f'DifferenceKit: {DK} @ {commit}')
except (OSError, subprocess.CalledProcessError):
    print(f'DifferenceKit: {DK}')
sources = dk_sources + [str(ROOT / 'Sources' / 'Core.swift')]
common = ['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5',
          '-module-cache-path',str(OUT / 'ModuleCache')]
mode = sys.argv[1] if len(sys.argv) > 1 else 'cpu'
if mode == 'cpu':
    subprocess.run(common + sources + [str(ROOT/'Sources'/'CPUMain.swift'),'-o',str(OUT/'cpu')],check=True)
elif mode == 'ui':
    app = OUT / 'ParadeDiffBench.app'
    app.mkdir(exist_ok=True)
    sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
    subprocess.run(common + ['-sdk',sdk,'-target','arm64-apple-ios17.0-simulator'] + sources +
                   [str(ROOT/'Sources'/'UIMain.swift'),'-o',str(app/'ParadeDiffBench')],check=True)
    with (app/'Info.plist').open('wb') as f:
        plistlib.dump({'CFBundleIdentifier':'dev.weixi.ParadeDiffBench','CFBundleName':'Parade Diff Bench',
            'CFBundleExecutable':'ParadeDiffBench','CFBundlePackageType':'APPL','CFBundleVersion':'1',
            'CFBundleShortVersionString':'1.0','MinimumOSVersion':'17.0','LSRequiresIPhoneOS':True,
            'UIDeviceFamily':[1,2],'UILaunchScreen':{},
            'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,
                'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Benchmark'}]}}},f)
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
else:
    raise SystemExit('mode must be cpu or ui')
