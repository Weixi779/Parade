#!/usr/bin/env python3
# Created by weixi on 2026/10/02.
"""Build the isolated typed-layout modules and optional simulator app."""

import argparse
import platform
import plistlib
import subprocess
from prepare import HERE, WORK, PACKAGE, prepare

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', action='store_true')
options = parser.parse_args()
prepare()
modules = WORK / 'Modules'
modules.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
common = ['xcrun', 'swiftc', '-swift-version', '6', '-sdk', sdk,
          '-target', f'{platform.machine()}-apple-ios16.0-simulator',
          '-module-cache-path', str(WORK / 'ModuleCache'), '-g']
for name, dependencies in [('Parade', []), ('StudySupport', ['-I', str(modules)])]:
    subprocess.run(common + dependencies + ['-parse-as-library', '-emit-module', '-emit-library', '-static',
        '-module-name', name, '-emit-module-path', str(modules / f'{name}.swiftmodule'),
        '-o', str(modules / f'lib{name}.a')]
        + [str(p) for p in sorted((PACKAGE / 'Sources' / name).rglob('*.swift'))], check=True)
if options.app:
    app = WORK / 'LayoutCompositionStudy.app'
    app.mkdir(exist_ok=True)
    subprocess.run(common + ['-parse-as-library', '-I', str(modules), '-L', str(modules),
        '-lParade', '-lStudySupport', '-module-name', 'LayoutCompositionStudy',
        str(HERE / 'Demo.swift'), '-o', str(app / 'LayoutCompositionStudy')], check=True)
    info = {'CFBundleIdentifier': 'dev.weixi.parade.layout-study', 'CFBundleName': 'Layout Study',
        'CFBundleDisplayName': 'Layout Study', 'CFBundleExecutable': 'LayoutCompositionStudy',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
        'MinimumOSVersion': '16.0', 'LSRequiresIPhoneOS': True, 'UIDeviceFamily': [1, 2],
        'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
        'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False,
            'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{'UISceneConfigurationName': 'Study'}]}}}
    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    print(app)
