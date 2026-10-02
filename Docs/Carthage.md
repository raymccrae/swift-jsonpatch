# Install with Carthage

Use Xcode 16+ and a Carthage version with XCFramework support (0.38+).
The framework supports iOS 13+, macOS 10.15+, tvOS 13+, and watchOS 6+.
The shared `JSONPatchMacFramework` scheme builds macOS. The `JSONPatchFramework` scheme builds iOS, tvOS, and watchOS. Both produce the `JSONPatch` module from the same sources.

Version 2.0.0 is unreleased. To validate this checkout, run from the repository directory:

```sh
carthage build --no-skip-current --use-xcframeworks --platform iOS,macOS,tvOS,watchOS
python3 Scripts/check-xcframework.py Carthage/Build/JSONPatch.xcframework ios macos tvos watchos
```

After v2.0.0 is released, add this dependency to your `Cartfile`:

```text
github "raymccrae/swift-jsonpatch" ~> 2.0
```

Build the dependency:

```sh
carthage update --use-xcframeworks --platform iOS,macOS,tvOS,watchOS
```

Add the generated `JSONPatch.xcframework` from `Carthage/Build` to your target's frameworks and select **Embed & Sign** for an application target. Import `JSONPatch` in Swift.
