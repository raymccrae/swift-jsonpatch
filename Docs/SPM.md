# Install with Swift Package Manager

Swift Package Manager is the recommended installation method for JSONPatch.
Use Swift 6.0+ and, for Xcode integration, Xcode 16+.

## Add the package in Xcode

1. Select **File > Add Package Dependencies**.
2. Enter the repository URL `https://github.com/raymccrae/swift-jsonpatch.git`.
3. Select **Up to Next Major Version** starting from **2.0.0**.
4. Add the `JSONPatch` product to your target.

## Configure Package.swift

Add the repository dependency and the `JSONPatch` product to your package:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YourProject",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/raymccrae/swift-jsonpatch.git", from: "2.0.0")
    ],
    targets: [
        .target(name: "YourProject", dependencies: [
            .product(name: "JSONPatch", package: "swift-jsonpatch")
        ])
    ],
    swiftLanguageModes: [.v6]
)
```

## Use a local checkout for development

In Xcode, select **File > Add Package Dependencies > Add Local** and choose this repository's directory. Add the `JSONPatch` product to your target.

In `Package.swift`, replace the repository dependency with a local path. Replace `../swift-jsonpatch` with your checkout's path:

```swift
.package(path: "../swift-jsonpatch")
```
