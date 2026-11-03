#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Build isolated research executables; no Parade package or upstream edits."""
import os, pathlib, plistlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent
DK = pathlib.Path(os.environ.get('DIFFERENCEKIT_PATH', ROOT.parent / '.build' / 'DifferenceKit' / 'Sources')).resolve()
if not list(DK.glob('*.swift')):
    raise SystemExit(f'DifferenceKit sources not found at {DK}; see ../README.md.')
print(f'DifferenceKit: {DK}')
OUT = ROOT / 'build'
OUT.mkdir(exist_ok=True)
sources = sorted(str(p) for p in DK.glob('*.swift')) + [str(ROOT.parent/'Sources'/'Core.swift'),
    str(ROOT/'Sources'/'SectionPlanner.swift'),str(ROOT/'Sources'/'Fixtures.swift')]
common = ['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5',
          '-module-cache-path',str(OUT / 'ModuleCache')]
mode = sys.argv[1] if len(sys.argv) > 1 else 'verify'
if mode == 'verify':
    subprocess.run(common + sources + [str(ROOT/'Sources'/'VerifyMain.swift'),'-o',str(OUT/'verify')],check=True)
elif mode == 'ui':
    app = OUT / 'ParadeDiffRound2.app'
    app.mkdir(exist_ok=True)
    sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
    subprocess.run(common + ['-sdk',sdk,'-target','arm64-apple-ios17.0-simulator'] + sources +
                   [str(ROOT/'Sources'/'UIMain.swift'),'-o',str(app/'ParadeDiffRound2')],check=True)
    with (app/'Info.plist').open('wb') as f:
        plistlib.dump({'CFBundleIdentifier':'dev.weixi.ParadeDiffRound2','CFBundleName':'Parade Diff Round 2',
            'CFBundleExecutable':'ParadeDiffRound2','CFBundlePackageType':'APPL','CFBundleVersion':'1',
            'CFBundleShortVersionString':'1.0','MinimumOSVersion':'17.0','LSRequiresIPhoneOS':True,
            'UIDeviceFamily':[1,2],'UILaunchScreen':{},
            'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,
                'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Benchmark'}]}}},f)
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
else:
    raise SystemExit('mode must be verify or ui')
