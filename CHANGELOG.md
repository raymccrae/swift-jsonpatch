# Changelog

## 2.0.0 — Unreleased

- Require Swift 6.0 and use Swift 6 language mode across SwiftPM, Xcode, and CocoaPods.
- Raise Apple deployment targets to macOS 10.15, iOS 13, tvOS 13, and watchOS 6. Drop support for older versions previously supported by the v1.0.6 CocoaPods package, whose minimums were macOS 10.12, iOS 11, tvOS 10, and watchOS 3.
- Replace `JSONError.patchTestFailed` Foundation payloads with Sendable `JSONError.Value` snapshots. See the [migration guide](Docs/Swift6Migration.md).
- Add Sendable conformance to `JSONPatch.ApplyOption`.
- Use toolchain-provided Swift Testing and packaged test fixtures.
- Repair standalone Xcode tests and support framework builds across Apple platforms.
- Add a dedicated macOS framework scheme so Carthage archives the correct platform.
- Add Swift 6 macOS/Linux CI and CocoaPods/Carthage distribution checks.
- Reject invalid JSON Pointer escape sequences.
- Reject moves into a source value's descendants before modifying the document.
- Support copying the document root into child paths.
- Preserve the actual `found` value in failed-test errors when the value exists.
- Throw recoverable errors for mutation paths whose parent is a scalar or null, consistently in Debug and Release builds.
- Preserve valid sequential array indices in generated patches by retaining remove/add operations instead of converting them to unsafe moves.
- Resolve paths beneath empty property names correctly, including relative patch application.
- Preserve unsigned 64-bit integers, including `UInt64.max`, during Codable encoding and decoding.
- Compare JSON Pointer tokens by Unicode scalars without normalization for recursive-move checks, pointer equality, and hashing. Canonically equivalent spellings remain distinct.
- Restrict the array `-` token to insertion destinations. Reject it when an existing array value is required, while preserving object properties named `-`.
- Reject URI-fragment forms in patch operation `path` and `from` fields through both Foundation and Codable decoding. Standalone `JSONPointer` parsing continues to support URI fragments.

## 1.0.6

- Add Linux support.
