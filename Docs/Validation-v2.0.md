# JSONPatch v2.0 validation

The repaired checkout passes the local SwiftPM, macOS, iOS simulator, and limited Carthage checks below. Release validation remains pending for Swift 6.0, Linux, CocoaPods, tvOS, watchOS, the full Carthage distribution, and installation from the published release tag.

This report supplements the original release review. Its results apply to the checkout, not to a published v2.0.0 release.

## Environment and revision

Validation date: October 3, 2026.

- Code and documentation revision: `8bd77c7d4f82786ece95c3631cac810715501700`.
- Host: Intel macOS 15.7.9, build `24G830`.
- Toolchain: Apple Swift 6.2.4, Xcode 26.3, build `17C529`.
- Carthage: 0.40.0.
- Test simulator: iPhone 15 Pro, iOS 17.2, identifier `40DEDA84-B74D-4C13-B64C-4B11F8761E69`.

SwiftPM results were collected before the final documentation commits. Sources and tests have not changed since `72042d7`.

## Completed checks

All standalone Xcode tests and SDK framework builds used `CODE_SIGNING_ALLOWED=NO` and `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`.

| Check | Result | Local evidence |
| --- | --- | --- |
| SwiftPM Debug, warnings as errors | Passed: 74 tests in 10 suites | `/tmp/jsonpatch-issue7-debug.log` |
| SwiftPM Release, warnings as errors | Passed: 74 tests in 10 suites | `/tmp/jsonpatch-issue7-release.log` |
| Standalone Xcode macOS tests | Passed: 74 tests in 10 suites | `macos-tests.log` in the Apple test log directory below |
| Standalone Xcode iOS simulator tests | Passed: 74 tests in 10 suites | `ios-tests.log` in the Apple test log directory below |
| Release macOS framework SDK build | Passed | `/tmp/jsonpatch-review-macos-framework.log` |
| Release iOS device framework SDK build | Passed | `/tmp/jsonpatch-review-ios-framework.log` |
| Release iOS simulator framework SDK build | Passed | `/tmp/jsonpatch-review-ios-simulator-framework.log` |
| Carthage build restricted to iOS and macOS | Passed | `carthage.log` in the isolated Carthage directory below |
| Restricted Carthage XCFramework validation | Passed: iOS device, iOS simulator, and macOS slices | `Carthage/Build/JSONPatch.xcframework` in the isolated Carthage directory below |

The Apple test log directory is `/private/var/folders/c6/yhpfyvmn345_5j0w1dl_mmsw0000gn/T/jsonpatch-apple.VbC1eU`. It also contains the test result bundles under `DerivedData/Logs/Test`.

The isolated Carthage directory is `/private/tmp/jsonpatch-carthage-w2rsuw1u`. It was populated with `git archive HEAD` at the revision above. The build did not use the checkout's output directories. These evidence paths are temporary local files and are not committed artifacts.

The usage-guide examples were also checked with a temporary harness: 11 existing snippets typechecked, the `.applyOnCopy` example compiled and printed `before`, and runtime probes confirmed partial mutation, ignored missing values, and failure of unsatisfied `test` operations. These checks supplement the regression suite.

## Commands used

The SwiftPM and standalone test commands were:

```sh
swift test -Xswiftc -warnings-as-errors
swift test --configuration release -Xswiftc -warnings-as-errors
bash Scripts/check-apple.sh tests
```

The three Release SDK builds used these commands:

```sh
xcodebuild -project JSONPatch.xcodeproj -derivedDataPath /tmp/jsonpatch-review-frameworks -scheme JSONPatchMacFramework -configuration Release -sdk macosx CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
xcodebuild -project JSONPatch.xcodeproj -derivedDataPath /tmp/jsonpatch-review-frameworks -scheme JSONPatchFramework -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
xcodebuild -project JSONPatch.xcodeproj -derivedDataPath /tmp/jsonpatch-review-frameworks -scheme JSONPatchFramework -configuration Release -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

The limited Carthage build and artifact check used:

```sh
carthage build --no-skip-current --use-xcframeworks --platform iOS,macOS --derived-data /private/tmp/jsonpatch-carthage-w2rsuw1u/DerivedData --project-directory /private/tmp/jsonpatch-carthage-w2rsuw1u --log-path /private/tmp/jsonpatch-carthage-w2rsuw1u/carthage.log
python3 /private/tmp/jsonpatch-carthage-w2rsuw1u/Scripts/check-xcframework.py /private/tmp/jsonpatch-carthage-w2rsuw1u/Carthage/Build/JSONPatch.xcframework ios macos
```

## Pending release checks

Run these checks in suitably provisioned environments before release. A successful SDK build does not establish successful packaging or runtime testing on another platform.

| Check | Status and next action |
| --- | --- |
| Minimum Swift 6.0 toolchain | Pending. Swift 6.0 is unavailable locally. Run Debug and Release tests with warnings as errors on that toolchain. |
| Linux | Pending. No local Linux or Docker environment is available. Run the regression suite on Linux, including unsigned-integer and Unicode cases. |
| CocoaPods | Pending. CocoaPods is not installed locally. Run `pod lib lint RMJSONPatch.podspec --fail-fast` in a provisioned environment. |
| tvOS and watchOS | Pending. No builds or tests for these platforms were run during this repair validation. |
| Full Carthage distribution | Pending. Run `carthage build --no-skip-current --use-xcframeworks --platform iOS,macOS,tvOS,watchOS`, then `python3 Scripts/check-xcframework.py Carthage/Build/JSONPatch.xcframework ios macos tvos watchos`. The restricted build above does not complete this check. |
| Published release installation | Pending until publication. Validate the podspec source tag and documented SwiftPM and Carthage dependency declarations against the actual `v2.0.0` tag, and update unreleased notices. |

No SDKs, simulator runtimes, package managers, or toolchains were installed for these checks. The release owner handles tags and publication.

## October 4, 2026 follow-up

The additional Unicode generation and patch-value fixes pass the local checks below at code revision `d8249c275cceccbdadbb937f2060de621d66749e`. These results supersede the October 3 test counts for this revision. The October 3 evidence above remains historical.

| Check | Result | Local evidence |
| --- | --- | --- |
| SwiftPM Debug, warnings as errors | Passed: 79 tests in 10 suites | `/tmp/jsonpatch-finding9-debug.log` |
| SwiftPM Release, warnings as errors | Passed: 79 tests in 10 suites | `/tmp/jsonpatch-finding9-release.log` |
| Standalone Xcode macOS tests | Passed: 79 tests in 10 suites | `macos-tests.log` in the follow-up Apple test log directory below |
| Standalone Xcode iOS simulator tests | Passed: 79 tests in 10 suites | `ios-tests.log` in the follow-up Apple test log directory below |

The follow-up Apple test log directory is `/private/var/folders/c6/yhpfyvmn345_5j0w1dl_mmsw0000gn/T/jsonpatch-apple.xjPsPQ`. It also contains the test result bundles under `DerivedData/Logs/Test`. The standalone tests used `bash Scripts/check-apple.sh tests` with code signing disabled and Swift warnings treated as errors. These evidence paths are temporary local files and are not committed artifacts.

Independent temporary runtime probes also passed. Unicode generation checks covered both review examples, mixed composed and decomposed keys containing `/` and `~`, and a nested Unicode object copy candidate in an array. The probes checked both mutable and immutable generation options against a recursive Foundation comparison that preserved the exact UTF-8 bytes of object keys. Patch-value checks applied the review's Codable patch three times to fresh empty objects and confirmed the same result and unchanged serialized patch each time. A derived patch with a later failing remove operation also preserved its serialized constants across two failed applications.

No fresh CI results were obtained. Swift 6.0, Linux, CocoaPods, tvOS, watchOS, the full Carthage distribution, and installation from the published release tag remain open release checks. The framework and restricted Carthage results above apply only to the October 3 revision; they were not rerun for this follow-up. No SDKs, simulator runtimes, package managers, or toolchains were installed. The release owner handles tags and publication.

## October 4, 2026 mutable-string follow-up

The residual mutable-string fix copies `NSMutableString` leaves in both platform branches of the dictionary deep-copy helper. It uses `mutableCopy()`, matching the array helper and preserving mutable result strings. Mutating a returned string therefore leaves the stored add/replace constant unchanged. These results apply to the checkout containing this fix, after the `3916171` reassessment.

| Check | Result | Local evidence |
| --- | --- | --- |
| SwiftPM Debug, warnings as errors | Passed: 82 tests in 10 suites | `/tmp/jsonpatch-strings-debug.log` |
| SwiftPM Release, warnings as errors | Passed: 82 tests in 10 suites | `/tmp/jsonpatch-strings-release.log` |

Regression tests cover dictionary strings, nested dictionaries, dictionaries inside arrays, and direct array strings. Patch tests cover add/replace at object, array, and root destinations, repeated applications, both copy options, and unchanged Foundation and Codable serialization after mutating returned strings. An independent probe reproduced the review's dictionary-string example and confirmed the patch stayed unchanged across two applications. It also confirmed that direct array strings remain independent when either the original or the copy is mutated. The probe source is `/tmp/jsonpatch-strings-probe/main.swift`; these evidence paths are temporary local files.

Linux runtime behavior remains unverified, although both dictionary code branches contain the repair. No standalone Xcode, SDK framework, or distribution checks were rerun for this fix. The earlier 79-test standalone Xcode results remain historical and do not validate the mutable-string repair. The pending release checks above remain open.
