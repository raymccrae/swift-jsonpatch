# JSONPatch Usage

## Key Type

| Type        | Description                                                  |
| ----------- | ------------------------------------------------------------ |
| JSONPatch   | A class representing a RFC6902 json-patch.                   |
| JSONPointer | A struct representing a RFC6901 json-pointer.                |
| JSONElement | A struct wrapper that holds a reference to an element of a json document compatible with JSONSerialization. |
| JSONError   | A enum representing all the errors that may be thrown by the methods within the JSONPatch library. |

## Creating JSONPatch Instance

JSONPatch library is designed to work flexibly to work with a number of scenarios. The JSONPatch class represents a [RFC6902](https://tools.ietf.org/html/rfc6902) json-patch instance. This section demonstrates a number of ways a JSONPatch instance can be instantiated. Note that JSONPatch instances are immutable and can not be modified after creation.

### Decoding a json-patch from Data

If you have a raw Data representation of the json-patch, then the below example shows the initialization. The data must represent a json document with a top-level json array as defined within the RFC6902 specification.

```swift
let data: Data = ... // wherever your app gets data from.
let patch = JSONPatch(data: data)
```

The data must be one of the supported encoding of [JSONSerialization](https://developer.apple.com/documentation/foundation/jsonserialization):- 

> The data must be in one of the 5 supported encodings listed in the JSON specification: UTF-8, UTF-16LE, UTF-16BE, UTF-32LE, UTF-32BE. The data may or may not have a BOM. The most efficient encoding to use for parsing is UTF-8, so if you have a choice in encoding the data passed to this method, use UTF-8.

### Decoding a json-patch from a sub-element of a json document (JSONSerialization)

The previous scenario works if your json-patch is availble in isolation, if the data represents only the json-patch. However, if the json-patch is a sub-element of a larger json document and your app is using JSONSerialization to parse that json document; then JSONPatch can be initialized from a NSArray. You will need to extract the subelement of the parsed json object to get the array representing the json-patch.

```swift
do {
    let jsonobj = try JSONSerialization.jsonObject(with: data)
    guard let jsondoc = jsonobj as? NSDictionary else { throw ParseError }
    guard let subelement = jsondoc["patch"] as? NSArray { throw ParseError }
    
    let patch = JSONPatch(jsonArray: subelement)
} catch {
    // handle error
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
    // handle error
}
```

### Generate a json-patch from the differences between two json documents

A json-patch can be computed from the differences between two json documents. The created json-patch will consist of all the operations required to transform the source json document into the target json document.

```swift
let sourceData = ... // a data representation of the before json document
let targetData = ... // a data representation of the after json document

let patch = try! JSONPatch(source: sourceData, target: targetData)
```

Alternatively if you would rather work with parsed json elements from JSONSerialization. Then wrap these elements in a JSONElement struct and initialise the JSONPatch with them. This approach can also be used when computing the patch based on sub-elements of the json document.

```swift
let source = ... // a JSONSerialization compatable json object - Before
let target = ... // a JSONSerialization compatable json object - After

let sourceElement = try! JSONElement(any: source)
let targetElement = try! JSONElement(any: target)

let patch = try! JSONPatch(source: sourceElement, target: targetElement)
```

## Applying a JSONPatch

A JSONPatch instance can be applied to a json document to result in a new transformed json document.

### Apply patch to a json document

JSONPatch can be applied to Data representations of a json document.

```swift
let sourceData = ... // a data representation of the before json document
let patch = ... // a json patch

let patchedData = try! patch.apply(to: sourceData)
```

Alternatively if you would rather work with parsed json elements from JSONSerialization. This approach has options to apply the patch inplace, which results in the apply process modifying (where possible) the original json document with the updates in the patch, avoiding making a copy of the original document.

```swift
var jsonObject = try! JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
let patch = ... // a json patch

jsonObject = try! patch.apply(to: jsonObject, inplace: true)
```

### Apply patch to a sub-element of a json document

A JSONPatch can be applied relative to a sub-element of a json document. This can be achieved by specifying a json-pointer to the sub-element to apply the patch. When specified the sub-element will be treated as the root element for the purposes of applying the patch.

```swift
let sourceData = ... // a data representation of the before json document
let patch = ... // a json patch
let pointer = try! JSONPointer(string: "/subelement")

let patchedData = try! patch.apply(to: sourceData, relativeTo: pointer)
```

## Serializing a JSONPatch

This section demonstrates a number of ways a JSONPatch instance can be serialized to Data.

### Convert JSONPatch to Data

A JSONPatch instance can supply a serialized Data representation by calling the data method. Resulting in a UTF-8 data repesentation of the json-patch.

```swift
let data = try! patch.data()
```

### Inserting a JSONPatch as a sub-element of a json document (JSONSerialization)

If the json-patch is a sub-element of a larger json document, then a JSONSerialization complient representation can be computed via the jsonArray property. This will create a json array compatible for JSONSerialization.

```swift
var dict: [String: Any] = [:]
dict["patch"] = patch.jsonArray

let data = try! JSONSerialization.data(withJSONObject: dict, options: [])
```

### Inserting a JSONPatch as a sub-element of a json document (JSONEncoder)

Alternatively if your app is using [Codable](https://developer.apple.com/documentation/swift/codable) then you can include the JSONPatch class in your type. JSONPatch is fully Codable.

```swift
struct Document: Codable {
    let patch: JSONPatch
}

do {
    var encoder = JSONEncoder()
    let data = try encoder.encode(doc)
} catch {
    // handle error
}
```

