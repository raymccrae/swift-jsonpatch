# JSONPatch - Swift 4/5 json-patch implementation
[![Apache 2 License](https://img.shields.io/badge/license-Apache%202-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Supported Platforms](https://img.shields.io/badge/platform-ios%20%7C%20macos%20%7C%20tvos-lightgrey.svg)](http://developer.apple.com)
[![Build System](https://img.shields.io/badge/dependency%20management-spm%20%7C%20cocoapods-yellow.svg)](https://swift.org/package-manager/)

JSONPatch is a a swift module implements json-patch [RFC6902](https://tools.ietf.org/html/rfc6902). JSONPatch uses [JSONSerialization](https://developer.apple.com/documentation/foundation/jsonserialization) from Foundation, and has no dependencies on third-party libraries.

The implementation uses the [JSON Patch Tests](https://github.com/json-patch/json-patch-tests) project for unit tests to validate its correctness.

# Release
1.0.2 - Support Swift 5

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

# License

Apache License v2.0
