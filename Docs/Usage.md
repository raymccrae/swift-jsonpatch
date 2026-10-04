# JSONPatch Usage

## Key Type

| Type        | Description                                                  |
| ----------- | ------------------------------------------------------------ |
| JSONPatch   | A class representing a RFC6902 json-patch.                   |
| JSONPointer | A struct representing a RFC6901 json-pointer.                |
| JSONElement | An enum wrapper that holds a reference to an element of a json document compatible with JSONSerialization. |
| JSONError   | A enum representing all the errors that may be thrown by the methods within the JSONPatch library. |

## Creating JSONPatch Instance

JSONPatch library is designed to work flexibly to work with a number of scenarios. The JSONPatch class represents a [RFC6902](https://tools.ietf.org/html/rfc6902) json-patch instance. This section demonstrates a number of ways a JSONPatch instance can be instantiated. The operations array is fixed after creation. Its values can retain mutable Foundation objects; see the [concurrency guide](Swift6Migration.md#use-jsonpatch-with-actors).

### Decoding a json-patch from Data

If you have a raw Data representation of the json-patch, then the below example shows the initialization. The data must represent a json document with a top-level json array as defined within the RFC6902 specification.

```swift
let data: Data = ... // wherever your app gets data from.
do {
    let patch = try JSONPatch(data: data)
    // Use the decoded patch here.
} catch {
    // Handle invalid JSON or patch operations, for example by reporting the error.
    print("Cannot decode patch: \(error)")
}
```

The data must be one of the supported encoding of [JSONSerialization](https://developer.apple.com/documentation/foundation/jsonserialization):- 

> The data must be in one of the 5 supported encodings listed in the JSON specification: UTF-8, UTF-16LE, UTF-16BE, UTF-32LE, UTF-32BE. The data may or may not have a BOM. The most efficient encoding to use for parsing is UTF-8, so if you have a choice in encoding the data passed to this method, use UTF-8.

### Decoding a json-patch from a sub-element of a json document (JSONSerialization)

The previous scenario works if your json-patch is availble in isolation, if the data represents only the json-patch. However, if the json-patch is a sub-element of a larger json document and your app is using JSONSerialization to parse that json document; then JSONPatch can be initialized from a NSArray. You will need to extract the subelement of the parsed json object to get the array representing the json-patch.

```swift
enum ParseError: Error {
    case invalidDocument
    case missingPatch
}

do {
    let jsonobj = try JSONSerialization.jsonObject(with: data)
    guard let jsondoc = jsonobj as? NSDictionary else { throw ParseError.invalidDocument }
    guard let subelement = jsondoc["patch"] as? NSArray else { throw ParseError.missingPatch }
    
    let patch = try JSONPatch(jsonArray: subelement)
} catch {
    print("Cannot decode patch: \(error)")
}
```

### Decoding a json-patch from a sub-element of a json document (JSONDecoder)

Alternatively if your app is using [Codable](https://developer.apple.com/documentation/swift/codable) then you can include the JSONPatch class in your type. JSONPatch is fully Codable.

```swift
struct Document: Codable {
    let patch: JSONPatch
}

do {
    let decoder = JSONDecoder()
    let doc = try decoder.decode(Document.self, from: data)
    
    let patch = doc.patch
} catch {
    print("Cannot decode patch: \(error)")
}
```

### Generate a json-patch from the differences between two json documents

A json-patch can be computed from the differences between two json documents. The created json-patch will consist of all the operations required to transform the source json document into the target json document.

```swift
let sourceData = ... // a data representation of the before json document
let targetData = ... // a data representation of the after json document

do {
    let patch = try JSONPatch(source: sourceData, target: targetData)
    // Use the generated patch here.
} catch {
    print("Cannot generate patch: \(error)")
}
```

Alternatively if you would rather work with parsed json elements from JSONSerialization. Then wrap these elements in a JSONElement enum and initialise the JSONPatch with them. This approach can also be used when computing the patch based on sub-elements of the json document.

```swift
let source = ... // a JSONSerialization compatable json object - Before
let target = ... // a JSONSerialization compatable json object - After

do {
    let sourceElement = try JSONElement(any: source)
    let targetElement = try JSONElement(any: target)

    let patch = try JSONPatch(source: sourceElement, target: targetElement)
    // Use the generated patch here.
} catch {
    print("Cannot generate patch: \(error)")
}
```

## Applying a JSONPatch

A JSONPatch instance can be applied to a json document to result in a new transformed json document.

### Apply patch to a json document

JSONPatch can be applied to Data representations of a json document.

```swift
let sourceData = ... // a data representation of the before json document
let patch = ... // a json patch

do {
    let patchedData = try patch.apply(to: sourceData)
    // Use the transformed document here.
} catch {
    print("Cannot apply patch: \(error)")
}
```

You can also apply a patch to a parsed JSON document. By default, `apply(to:options:)` modifies mutable containers in the original document where possible. Assign the returned value to keep changes that replace the document's root.

```swift
let patch = ... // a json patch

do {
    var jsonObject = try JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
    jsonObject = try patch.apply(to: jsonObject, options: [])
    // Use the transformed document here.
} catch {
    print("Cannot parse document or apply patch: \(error)")
}
```

### Handle partial changes when a patch fails

Patch operations run in order. If an operation throws, earlier changes are not rolled back. When you apply a patch directly to mutable Foundation containers, the original document can be left partially changed. Even a single `move` operation can remove its source before inserting it at the destination fails.

Applying a patch deep-copies its `add` and `replace` values before inserting them into the document, including nested containers and root replacements. Later operations and container changes to the returned document therefore do not rewrite those stored patch values, even if application fails. You can apply the same patch to fresh identical documents and obtain the same result. If you retain a mutable Foundation value supplied when constructing a patch, changing that value can still change the patch; see the [concurrency guide](Swift6Migration.md#use-jsonpatch-with-actors).

To preserve the original document, use `JSONPatch.apply(to:options:)` with `.applyOnCopy`. This method copies the document before applying the operations. In this example, the second operation fails because `/missing` does not exist, but the original `name` remains `"before"`:

```swift
import Foundation
import JSONPatch

let source = NSMutableDictionary(dictionary: ["name": "before"])
let patchData = Data(#"[{"op":"replace","path":"/name","value":"after"},{"op":"remove","path":"/missing"}]"#.utf8)

do {
    let patch = try JSONPatch(data: patchData)
    _ = try patch.apply(to: source as Any, options: [.applyOnCopy])
} catch JSONError.referencesNonexistentValue {
    print("Cannot apply patch: a referenced value does not exist.")
} catch {
    print("Cannot decode or apply patch: \(error)")
}

print(source["name"] as? String ?? "") // before
```

With `options: []`, the same example leaves `source["name"]` set to `"after"` when the patch throws. The `.applyOnCopy` behavior belongs to `JSONPatch.apply(to:options:)` for an `Any` document. Passing this option to `JSONElement.apply(patch:options:)` does not copy the element. The `Data` overload parses a separate document and returns transformed data only on success, so its input `Data` is unaffected by application failures.

The `.ignoreNonexistentValues` option is a nonstandard extension to JSON Patch. It catches `JSONError.referencesNonexistentValue` raised while applying an operation and continues with the remaining operations. It does not roll back changes made by that operation: a `move` can remove its source, fail to find its destination, and then allow the patch to continue without the source value. It does not suppress failed `test` operations, including tests of missing paths, or errors from invalid patch documents. A missing path used by `.relative(to:)` also fails before any operation runs and is not ignored.

For parsed documents, pass this option as `options: [.ignoreNonexistentValues]`. For `Data`, use `applyingOptions: [.ignoreNonexistentValues]`.

### Apply patch to a sub-element of a json document

A JSONPatch can be applied relative to a sub-element of a json document. This can be achieved by specifying a json-pointer to the sub-element to apply the patch. When specified the sub-element will be treated as the root element for the purposes of applying the patch.

```swift
let sourceData = ... // a data representation of the before json document
let patch = ... // a json patch
do {
    let pointer = try JSONPointer(string: "/subelement")
    let patchedData = try patch.apply(to: sourceData, applyingOptions: [.relative(to: pointer)])
    // Use the transformed document here.
} catch {
    print("Cannot apply patch: \(error)")
}
```

## Serializing a JSONPatch

This section demonstrates a number of ways a JSONPatch instance can be serialized to Data.

### Convert JSONPatch to Data

A JSONPatch instance can supply a serialized Data representation by calling the data method. Resulting in a UTF-8 data repesentation of the json-patch.

```swift
do {
    let data = try patch.data()
    // Send or store the serialized patch here.
} catch {
    print("Cannot serialize patch: \(error)")
}
```

### Inserting a JSONPatch as a sub-element of a json document (JSONSerialization)

If the json-patch is a sub-element of a larger json document, then a JSONSerialization complient representation can be computed via the jsonArray property. This will create a json array compatible for JSONSerialization.

```swift
var dict: [String: Any] = [:]
dict["patch"] = patch.jsonArray

do {
    let data = try JSONSerialization.data(withJSONObject: dict, options: [])
    // Send or store the serialized document here.
} catch {
    print("Cannot serialize document: \(error)")
}
```

### Inserting a JSONPatch as a sub-element of a json document (JSONEncoder)

Alternatively if your app is using [Codable](https://developer.apple.com/documentation/swift/codable) then you can include the JSONPatch class in your type. JSONPatch is fully Codable.

```swift
struct Document: Codable {
    let patch: JSONPatch
}

let doc = Document(patch: patch)

do {
    let encoder = JSONEncoder()
    let data = try encoder.encode(doc)
    // Send or store the serialized document here.
} catch {
    print("Cannot serialize document: \(error)")
}
```


## Swift 6 errors and concurrency

See the [Swift 6 migration guide](Swift6Migration.md) for failed-test snapshots, missing-versus-null behavior, and actor usage.
