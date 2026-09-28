#!/usr/bin/env python3
# Created by weixi on 2026/09/29.
"""Build the standalone scroll-position research demo against Parade's public API."""

import pathlib
import platform
import plistlib
import subprocess

source = pathlib.Path(__file__).resolve().parent
root = source.parent.parent
build = root / ".build" / "ScrollPositionStudy"
modules = build / "Modules"
app = build / "ScrollPositionStudy.app"
modules.mkdir(parents=True, exist_ok=True)
app.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
common = ["xcrun", "swiftc", "-swift-version", "6", "-sdk", sdk,
          "-target", f"{platform.machine()}-apple-ios16.0-simulator",
          "-module-cache-path", str(build / "ModuleCache"), "-g"]
subprocess.run(common + ["-parse-as-library", "-emit-module", "-emit-library", "-static",
                       "-module-name", "Parade", "-emit-module-path", str(modules / "Parade.swiftmodule"),
                       "-o", str(modules / "libParade.a")]
               + [str(p) for p in sorted((root / "Sources" / "Parade").rglob("*.swift"))], check=True)
subprocess.run(common + ["-parse-as-library", "-I", str(modules), "-L", str(modules), "-lParade",
                       "-module-name", "ScrollPositionStudy", str(source / "Demo.swift"),
                       "-o", str(app / "ScrollPositionStudy")], check=True)
info = {
    "CFBundleIdentifier": "dev.weixi.parade.scroll-study", "CFBundleName": "Scroll Study",
    "CFBundleDisplayName": "Scroll Study", "CFBundleExecutable": "ScrollPositionStudy",
    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
    "MinimumOSVersion": "16.0", "LSRequiresIPhoneOS": True, "UIDeviceFamily": [1, 2],
    "UILaunchScreen": {}, "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False,
        "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{"UISceneConfigurationName": "Demo"}]}},
}
with (app / "Info.plist").open("wb") as file:
    plistlib.dump(info, file)
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
print(app)
