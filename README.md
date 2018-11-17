# JSONPatch - Swift 4 json-patch implementation
JSONPatch is a a swift module implements json-patch [RFC6902](https://tools.ietf.org/html/rfc6902). JSONPatch uses [JSONSerialization](https://developer.apple.com/documentation/foundation/jsonserialization) from Foundation, and has no dependencies on third-party libraries.

The implementation uses the [JSON Patch Tests](https://github.com/json-patch/json-patch-tests) project for unit tests to validate its correctness.

The module currently only supports applying json-patches, and does not support generating a patch based on the differences between two json documents.

# Release
0.1 - Initial Release

# Usage
```swift
import JSONPatch

let jsonstr = """
              {"foo": "bar"}
              """
let patchstr = """
               {"op": "add", "path": "/baz", "value": "qux"}
               """

let json = Data(jsonstr.utf8)
let patch = try! JSONPatch(data: Data(patchstr.utf8))
let patched = try! patch.apply(to: json)
```


# License

Apache License v2.0