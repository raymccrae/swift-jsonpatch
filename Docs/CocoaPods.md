# Install with CocoaPods

For new integrations, use [Swift Package Manager](SPM.md), the recommended installation method.
If your project uses CocoaPods, you can install JSONPatch directly from a Git release tag.

Use Xcode 16+ and Swift 6. The library supports iOS 13+, macOS 10.15+, tvOS 13+, and watchOS 6+.
See the [Swift 6 migration guide](Swift6Migration.md) for the API changes and increased deployment targets in version 2.0.

## Install version 2.0 from Git

**Version 2.0.0 is unreleased.** After the `v2.0.0` tag is published, replace your existing `RMJSONPatch` declaration in your `Podfile` with:

```ruby
pod 'RMJSONPatch', :git => 'https://github.com/raymccrae/swift-jsonpatch.git', :tag => 'v2.0.0'
```

Run `pod install`, open the generated workspace, and import `JSONPatch` in Swift.
For later releases, change `:tag` to the release tag you want to install.

This configuration downloads the source and podspec from Git rather than looking up the version in public Trunk.
It continues to work after Trunk becomes read-only; a GitHub release does not need a `pod trunk push` for this installation method.
See the [CocoaPods documentation on Git dependencies](https://guides.cocoapods.org/using/the-podfile.html#from-a-podspec-in-the-root-of-a-library-repo).

## Understand the Trunk transition

The [CocoaPods Trunk read-only plan](https://blog.cocoapods.org/CocoaPods-Specs-Repo/) schedules a test shutdown of publishing for November 1–7, 2026, and a permanent switch to read-only on December 2, 2026.
After the permanent switch, public Trunk will accept neither new pods nor new versions of existing pods. Previously published versions will remain available.
Creating a Git tag alone does not make that version available through a plain `pod 'RMJSONPatch'` declaration. Use the Git configuration above or migrate to Swift Package Manager to install releases that are not published to Trunk.

If you need to stay on version 1.x for an older toolchain, OS target, or API, constrain your existing Trunk dependency:

```ruby
pod 'RMJSONPatch', '~> 1.0'
```

This excludes version 2.0. Keep your `Podfile.lock` under version control to preserve the resolved version.

## Use a local checkout

To try version 2.0 before release, add a local dependency to your `Podfile`:

```ruby
platform :ios, '13.0'
use_frameworks!

target 'YourApp' do
  pod 'RMJSONPatch', :path => '../swift-jsonpatch'
end
```

Replace `YourApp` with your target name and `../swift-jsonpatch` with the checkout's path. Run `pod install`, open the generated workspace, and import `JSONPatch` in Swift.

To validate local changes, run:

```sh
pod lib lint RMJSONPatch.podspec --fail-fast
```
