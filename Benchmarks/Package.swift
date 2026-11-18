// swift-tools-version:6.0
import Foundation
import PackageDescription

let libraryPath = ProcessInfo.processInfo.environment["JSONPATCH_BENCHMARK_LIBRARY_PATH"] ?? ".."

let package = Package(
    name: "PatchGenerationBenchmarks",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PatchGenerationBenchmarks", targets: ["PatchGenerationBenchmarks"])],
    dependencies: [.package(name: "JSONPatch", path: libraryPath)],
    targets: [
        .executableTarget(name: "PatchGenerationBenchmarks", dependencies: [
            .product(name: "JSONPatch", package: "JSONPatch")
        ]),
        .testTarget(name: "BenchmarkSupportTests", dependencies: ["PatchGenerationBenchmarks"])
    ]
)
