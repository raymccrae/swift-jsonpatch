// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JSONPatch",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "JSONPatch",
            targets: ["JSONPatch"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "JSONPatch",
            dependencies: [],
            exclude: ["Info.plist"]),
        .testTarget(
            name: "JSONPatchTests",
            dependencies: ["JSONPatch"],
            path: "Tests",
            exclude: ["JSONPatchTests/Info.plist"],
            resources: [
                .process("JSONPatchTests/tests.json"),
                .process("JSONPatchTests/spec_tests.json"),
                .process("JSONPatchTests/extra.json"),
                .process("JSONPatchTests/bigexample1.json"),
                .process("JSONPatchTests/bigexample2.json"),
                .process("JSONPatchTests/bigpatch.json")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
