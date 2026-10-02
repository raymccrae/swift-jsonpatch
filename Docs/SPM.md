# Install with Swift Package Manager

Use Swift 6.0+ and, for Xcode integration, Xcode 16+.
Version 2.0.0 is unreleased. To try this checkout, add it as a local package.

## Add a local package in Xcode

1. Select **File > Add Package Dependencies**.
2. Select **Add Local** and choose this repository's directory.
3. Add the `JSONPatch` product to your target.

After v2.0.0 is released, use the repository URL `https://github.com/raymccrae/swift-jsonpatch.git` and select version 2.0.0 or later instead.

## Configure Package.swift

For development, point the dependency at your local checkout. Replace `../swift-jsonpatch` with its path:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YourProject",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    dependencies: [
        .package(path: "../swift-jsonpatch")
    ],
    targets: [
        .target(name: "YourProject", dependencies: [
            .product(name: "JSONPatch", package: "swift-jsonpatch")
        ])
    ],
    swiftLanguageModes: [.v6]
)
```

After v2.0.0 is released, replace the local dependency with:

```swift
.package(url: "https://github.com/raymccrae/swift-jsonpatch.git", from: "2.0.0")
```
