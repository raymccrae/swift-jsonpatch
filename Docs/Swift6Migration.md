# Migrate to JSONPatch 2.0

Version 2.0 requires Swift 6.0+. Use Xcode 16+ for Apple development.
All installation methods use the same library minimums: macOS 10.15, iOS 13, tvOS 13, and watchOS 6. Linux remains supported through Swift Package Manager.

Version 2.0 drops support for older Apple OS versions previously supported by the v1.0.6 CocoaPods package. Its minimums were macOS 10.12, iOS 11, tvOS 10, and watchOS 3. If your app targets an older OS version, raise its deployment target before upgrading to version 2.0.

## Read failed-test values

`JSONError.patchTestFailed` now carries immutable `JSONError.Value` snapshots instead of `Any` values. The case retains its `path`, `expected`, and `found` labels.

Before version 2.0, callers used the Foundation value directly:

```swift
catch JSONError.patchTestFailed(let path, let expected, let found) {
    let expectedElement = try JSONElement(any: expected)
    // Inspect found as an optional Foundation value.
}
```

In version 2.0, decode the snapshot when you need a Foundation object:

```swift
catch JSONError.patchTestFailed(let path, let expected, let found) {
    let expectedElement = try JSONElement(any: expected.jsonObject())
    if let found {
        let foundElement = try JSONElement(any: found.jsonObject())
        print(path, expectedElement, foundElement)
    } else {
        print("Missing path:", path)
    }
}
```

A missing path produces `found == nil`. JSON null produces a non-nil snapshot whose `jsonObject()` returns `NSNull`.
Snapshots capture their values when the error is created. Mutating the original dictionaries, arrays, or strings afterward does not change the error.
Error equality continues to compare failed-test paths, rather than snapshot contents.

You can also decode the snapshot's UTF-8 JSON `data` with `JSONDecoder`, or create a snapshot with `try JSONError.Value(jsonObject: value)`.
The initializer supports JSON fragments such as strings, numbers, booleans, and null. Unsupported objects and non-finite numbers throw `JSONError.invalidObjectType`.
Each call to `jsonObject()` creates a fresh Foundation representation. Keep that decoded object within the receiving actor or task.

## Use JSONPatch with actors

`JSONPointer`, `JSONPatch.ApplyOption`, `JSONError`, and its `Value` snapshots are Sendable.
`JSONPatch`, `JSONPatch.Operation`, and `JSONElement` retain Foundation references and can include mutable containers. Keep those instances within one actor or task, and serialize values to `Data` before transferring them.
The `operations` array is fixed after construction. Application deep-copies `add` and `replace` values, so later operations and changes to containers or mutable strings in the result do not rewrite those stored values. If you retain mutable Foundation values supplied when constructing a patch, you can still change the patch by mutating those references.

Create and apply a patch inside the actor that owns the work:

```swift
import Foundation
import JSONPatch

actor PatchWorker {
    func apply(document: Data, patchData: Data,
               options: [JSONPatch.ApplyOption] = []) throws -> Data {
        let patch = try JSONPatch(data: patchData)
        return try patch.apply(to: document, applyingOptions: options)
    }
}

let worker = PatchWorker()
let result = try await worker.apply(
    document: Data(#"{"value":1}"#.utf8),
    patchData: Data(#"[{"op":"replace","path":"/value","value":2}]"#.utf8))
```

Errors can propagate across that actor boundary. Snapshot their payloads back to Foundation only where you consume them.
The library remains synchronous and does not impose main-actor isolation.

## Run tests

Tests use the Swift Testing copy included with Swift 6. No external Testing or SwiftSyntax dependency is needed.
If you built an earlier checkout with the external Testing dependency, clear the old compiled modules once before testing:

```sh
swift package clean
swift test -Xswiftc -warnings-as-errors
```

Test fixtures load from packaged resources, so they do not require a repository working directory.
The standalone Xcode test target uses macOS 14+ or iOS/tvOS 17+ test hosts. Library deployment targets remain lower.
