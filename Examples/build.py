#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Build the public-API example app for the selected iOS Simulator architecture."""

import argparse
import pathlib
import platform
import plistlib
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("arm64", "x86_64"), default=platform.machine())
    options = parser.parse_args()

    examples = pathlib.Path(__file__).resolve().parent
    root = examples.parent
    build = root / ".build" / "Examples"
    modules = build / "Modules"
    app = build / "ParadeExamples.app"
    modules.mkdir(parents=True, exist_ok=True)
    app.mkdir(parents=True, exist_ok=True)

    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True
    ).strip()
    common = [
        "xcrun", "swiftc", "-swift-version", "6", "-sdk", sdk,
        "-target", f"{options.arch}-apple-ios16.0-simulator",
        "-module-cache-path", str(build / "ModuleCache"), "-g",
    ]
    sources = sorted((root / "Sources" / "Parade").rglob("*.swift"))
    subprocess.run(common + [
        "-parse-as-library", "-emit-module", "-emit-library", "-static",
        "-module-name", "Parade", "-emit-module-path", str(modules / "Parade.swiftmodule"),
        "-o", str(modules / "libParade.a"),
    ] + [str(source) for source in sources], check=True)
    subprocess.run(common + [
        "-parse-as-library", "-I", str(modules), "-L", str(modules), "-lParade",
        "-module-name", "ParadeExamples", str(examples / "ParadeExamples.swift"),
        str(examples / "SimulatorApp.swift"), "-o", str(app / "ParadeExamples"),
    ], check=True)

    info = {
        "CFBundleIdentifier": "dev.weixi.parade.examples",
        "CFBundleName": "Parade Examples",
        "CFBundleDisplayName": "Parade Examples",
        "CFBundleExecutable": "ParadeExamples",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0",
        "MinimumOSVersion": "16.0",
        "LSRequiresIPhoneOS": True,
        "UIDeviceFamily": [1, 2],
        "UILaunchScreen": {},
        "UIApplicationSceneManifest": {
            "UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {
                "UIWindowSceneSessionRoleApplication": [{"UISceneConfigurationName": "Default"}]
            },
        },
    }
    with (app / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    print(app)


if __name__ == "__main__":
    main()
