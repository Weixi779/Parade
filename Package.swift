// swift-tools-version: 6.0
//
//  Created by weixi on 2026/9/17.
//

import PackageDescription

let package = Package(
    name: "Parade",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "Parade",
            targets: ["Parade"]
        ),
    ],
    targets: [
        .target(name: "Parade"),
        .target(name: "ParadeLayoutSupport", dependencies: ["Parade"], path: "Tests/LayoutSupport"),
        .testTarget(name: "ParadeTests", dependencies: ["Parade", "ParadeLayoutSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
