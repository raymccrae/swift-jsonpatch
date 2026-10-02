# JSONPatch — Swift 6 JSON Patch implementation
[![Apache 2 License](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Supported Platforms](https://img.shields.io/badge/platform-ios%20%7C%20macos%20%7C%20tvos%20%7C%20watchos%20%7C%20linux-lightgrey.svg)](http://developer.apple.com)
[![Build System](https://img.shields.io/badge/dependency%20management-spm%20%7C%20cocoapods%20%7C%20carthage-yellow.svg)](https://swift.org/package-manager/)

JSONPatch is a Swift library that implements JSON Patch [RFC6902](https://tools.ietf.org/html/rfc6902). JSONPatch uses [JSONSerialization](https://developer.apple.com/documentation/foundation/jsonserialization) from Foundation, and has no dependencies on third-party libraries.

The implementation uses the [JSON Patch Tests](https://github.com/json-patch/json-patch-tests) project for unit tests to validate its correctness.

## Requirements

Use Swift 6.0 or later. Apple development requires Xcode 16 or later.
The library supports macOS 10.15+, iOS 13+, tvOS 13+, watchOS 6+, and Linux.
Tests run on macOS 14+ or iOS/tvOS 17+ hosts; these test requirements do not change the library's deployment targets.

## Release

**2.0.0 is unreleased.** This checkout contains the Swift 6 migration.
See the [migration guide](Docs/Swift6Migration.md) for the breaking error-payload change and the [changelog](CHANGELOG.md) for release notes.
Version 1.0.6 added Linux support.

# Installation

## CocoaPods
See [CocoaPods.md](Docs/CocoaPods.md)

## Swift Package Manager
See [SPM.md](Docs/SPM.md)

## Carthage
See [Carthage.md](Docs/Carthage.md)

# Usage

A more detailed explanation of JSONPatch is given in [Usage.md](Docs/Usage.md).

## Applying Patches
```swift
import JSONPatch

let sourceData = Data("""
                      {"foo": "bar"}
                      """.utf8)
let patchData = Data("""
                     [{"op": "add", "path": "/baz", "value": "qux"}]
                     """.utf8)

let patch = try! JSONPatch(data: patchData)
let patched = try! patch.apply(to: sourceData)
```

## Generating Patches
```swift
import JSONPatch

let sourceData = Data("""
                      {"foo": "bar"}
                      """.utf8)
let targetData = Data("""
                      {"foo": "bar", "baz": "qux"}
                      """.utf8)
let patch = try! JSONPatch(source: sourceData, target: targetData)
let patchData = try! patch.data()
```

## Concurrency

`JSONPointer`, `JSONPatch.ApplyOption`, and `JSONError` can cross actor boundaries.
Keep `JSONPatch`, its operations, and `JSONElement` within one actor or task because they can retain mutable Foundation objects.
Transfer JSON `Data` between actors and create the patch inside the receiving actor.
See the [concurrency example](Docs/Swift6Migration.md#use-jsonpatch-with-actors).

## Development

Swift Testing is supplied by the toolchain. Run both configurations with compiler warnings treated as errors:

```sh
swift test -Xswiftc -warnings-as-errors
swift test --configuration release -Xswiftc -warnings-as-errors
```

On macOS, validate the standalone project and framework builds:

```sh
bash Scripts/check-apple.sh tests
bash Scripts/check-apple.sh frameworks
pod lib lint RMJSONPatch.podspec --fail-fast
carthage build --no-skip-current --use-xcframeworks --platform iOS,macOS,tvOS,watchOS
python3 Scripts/check-xcframework.py Carthage/Build/JSONPatch.xcframework ios macos tvos watchos
```

The Xcode test check requires an installed iPhone simulator runtime. CocoaPods and Carthage must be installed for their respective checks.
GitHub Actions runs Swift 6.0 and 6.2 tests on macOS and Linux, plus Apple distribution checks.

# License

Apache License v2.0
