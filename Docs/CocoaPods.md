# Install with CocoaPods

Use Xcode 16+ and Swift 6. The library supports iOS 13+, macOS 10.15+, tvOS 13+, and watchOS 6+.
Version 2.0.0 is unreleased. To use this checkout, add a local dependency to your `Podfile`:

```ruby
platform :ios, '13.0'
use_frameworks!

target 'YourApp' do
  pod 'RMJSONPatch', :path => '../swift-jsonpatch'
end
```

Replace `YourApp` with your target name and `../swift-jsonpatch` with the checkout's path. Run `pod install`, open the generated workspace, and import `JSONPatch` in Swift.

After v2.0.0 is released, use the release tag:

```ruby
pod 'RMJSONPatch', :git => 'https://github.com/raymccrae/swift-jsonpatch.git', :tag => 'v2.0.0'
```

To validate local changes, run:

```sh
pod lib lint RMJSONPatch.podspec --fail-fast
```
