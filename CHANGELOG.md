# Changelog

## 2.0.0 — Unreleased

- Require Swift 6.0 and use Swift 6 language mode across SwiftPM, Xcode, and CocoaPods.
- Align Apple deployment targets: macOS 10.15, iOS 13, tvOS 13, and watchOS 6.
- Replace `JSONError.patchTestFailed` Foundation payloads with Sendable `JSONError.Value` snapshots. See the [migration guide](Docs/Swift6Migration.md).
- Add Sendable conformance to `JSONPatch.ApplyOption`.
- Use toolchain-provided Swift Testing and packaged test fixtures.
- Repair standalone Xcode tests and support framework builds across Apple platforms.
- Add a dedicated macOS framework scheme so Carthage archives the correct platform.
- Add Swift 6 macOS/Linux CI and CocoaPods/Carthage distribution checks.

## 1.0.6

- Add Linux support.
