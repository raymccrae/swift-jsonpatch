JSONPatch 2.0.0 updates the library to Swift 6 and fixes JSON Patch correctness and Linux portability issues.

## Breaking changes

- Requires Swift 6.0+ and Xcode 16+ for Apple development.
- Minimum library deployment targets are macOS 10.15, iOS 13, tvOS 13, and watchOS 6.
- `JSONError.patchTestFailed` now carries Sendable `JSONError.Value` snapshots instead of Foundation `Any` payloads. Use `jsonObject()` to obtain a Foundation representation.

See the [Swift 6 migration guide](https://github.com/raymccrae/swift-jsonpatch/blob/v2.0.0/Docs/Swift6Migration.md) for upgrading existing applications.

## Improvements and fixes

- Add Sendable conformance to application options and error snapshots, with documented actor boundaries.
- Correct JSON Pointer validation, recursive moves, root copies, array indices, and exact Unicode property handling.
- Preserve stored patch values across repeated applications and mutations of returned documents.
- Preserve integer precision, nested mutable containers, and boolean equality across Darwin and Linux.
- Validate SwiftPM, standalone Xcode builds, CocoaPods, and Carthage distribution through CI.

The complete changes are listed in the [changelog](https://github.com/raymccrae/swift-jsonpatch/blob/v2.0.0/CHANGELOG.md).

## Installation

[Swift Package Manager](https://github.com/raymccrae/swift-jsonpatch/blob/v2.0.0/Docs/SPM.md) is recommended. Add the repository URL with version 2.0.0 or later within the 2.x series.

CocoaPods users can install directly from Git, including after public Trunk becomes read-only:

```ruby
pod 'RMJSONPatch', :git => 'https://github.com/raymccrae/swift-jsonpatch.git', :tag => 'v2.0.0'
```

[Carthage instructions](https://github.com/raymccrae/swift-jsonpatch/blob/v2.0.0/Docs/Carthage.md) are also available.

## Validation and compatibility

The release source passed all five CI jobs: Swift 6.0.3/6.2 Linux tests, Xcode 16.2/26.3 macOS and iOS simulator tests, and Apple framework/CocoaPods/Carthage distribution checks.

Standalone Xcode 27.1 builds reject the macOS 10.15 deployment target; Xcode 16.2 and 26.3 are the verified standalone configurations. See the [validation report](https://github.com/raymccrae/swift-jsonpatch/blob/v2.0.0/Docs/Validation-v2.0.md).
