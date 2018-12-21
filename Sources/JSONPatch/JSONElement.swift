//
//  JSONElement.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// JSON Element holds a reference an element of the parsed JSON structure
/// produced by JSONSerialization.
public enum JSONElement {
    case object(value: NSDictionary)
    case mutableObject(value: NSMutableDictionary)
    case array(value: NSArray)
    case mutableArray(value: NSMutableArray)
    case string(value: NSString)
    case number(value: NSNumber)
    case null
}

extension JSONElement {

    public init(_ value: String) {
        self = .string(value: value as NSString)
    }

    public init(_ value: Int) {
        self = .number(value: value as NSNumber)
    }

    public init(_ value: Double) {
        self = .number(value: value as NSNumber)
    }

    public init(_ value: Bool) {
        self = .number(value: value as NSNumber)
    }
}

extension JSONElement {

    /// The raw value of the underlying JSON representation.
    public var rawValue: Any {
        switch self {
        case .object(let value):
            return value
        case .mutableObject(let value):
            return value
        case .array(let value):
            return value
        case .mutableArray(let value):
            return value
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .null:
            return NSNull()
        }
    }

    /// Indicates if the receiver is a container element (dictionary or array).
    public var isContainer: Bool {
        switch self {
        case .object, .mutableObject, .array, .mutableArray:
            return true
        default:
            return false
        }
    }

    /// Indicates if the receiver is a mutable container (dictionary or array).
    public var isMutable: Bool {
        switch self {
        case .mutableObject, .mutableArray:
            return true
        case .object, .array, .string, .number, .null:
            return false
        }
    }

    /// Initialize a JSONElement with that is compatable with JSONSerialization.
    /// See JSONSerialization.isValidJSONObject for more details.
    ///
    /// - Parameters:
    ///   - any: The raw value.
    public init(any: Any) throws {
        switch any {
        case let dict as NSMutableDictionary:
            self = .mutableObject(value: dict)
        case let dict as NSDictionary:
            self = .object(value: dict)
        case let array as NSMutableArray:
            self = .mutableArray(value: array)
        case let array as NSArray:
            self = .array(value: array)
        case let str as NSString:
            self = .string(value: str)
        case let num as NSNumber:
            self = .number(value: num)
        case is NSNull:
            self = .null
        default:
            throw JSONError.invalidObjectType
        }
    }

    /// Creates a new JSONElement with a copied raw value of the reciever.
    ///
    /// - Returns: A JSONElement representing a copy of the reciever.
    public func copy() -> JSONElement {
        switch rawValue {
        case let dict as NSDictionary:
            return try! JSONElement(any: dict.deepMutableCopy())
        case let arr as NSArray:
            return try! JSONElement(any: arr.deepMutableCopy())
        case let null as NSNull:
            return try! JSONElement(any: null)
        case let obj as NSObject:
            return try! JSONElement(any: obj.mutableCopy())
        default:
            fatalError("JSONElement contained non-NSObject")
        }
    }

    // MARK: - Container Helper Methods

    /// Converts the receiver json element from a nonmutable container to a
    /// mutable container. .object will become .mutableObject and .array becomes
    /// .mutableArray. The raw value container will be copied to its mutable
    /// equivalent (e.g. NSMutableArray & NSMutableDictionary). This does NOT cause
    /// a deep copy. Only the reciever's raw value is copied to a new mutable container.
    /// If a deep copy is required then see the copy method.
    /// If the receiver is already mutable then this method has no effect.
    private mutating func makeMutable() {
        switch self {
        case .object(let dictionary):
            let mutable = NSMutableDictionary(dictionary: dictionary)
            self = .mutableObject(value: mutable)
        case .array(let array):
            let mutable = NSMutableArray(array: array)
            self = .mutableArray(value: mutable)
        case .mutableObject, .mutableArray:
            break
        case .string, .number, .null:
            assertionFailure("Unsupported type to make mutable")
            break
        }
    }

    /// Converts the json elements along the path of evaluation for a json pointer into
    /// mutable equivalents.
    ///
    /// - Parameters:
    ///   - pointer: The json pointer to identify the path of json element containers.
    /// - Returns: The last json element in the path.
    private mutating func makePathMutable(_ pointer: JSONPointer) throws -> JSONElement {
        if !self.isMutable {
            self.makeMutable()
        }

        guard pointer.string != "/" else {
            return self
        }

        var element = self
        for component in pointer {
            var child = try element.value(for: component)
            if !child.isMutable {
                child.makeMutable()
                try element.setValue(child, component: component, replace: true)
            }
            element = child
        }

        return element
    }

    /// This method is used to evalute a single component of a JSON Pointer.
    /// If the receiver represents a container (dictionary or array) with the JSON
    /// structure, then this method will get the value within the container referenced
    /// by the component of the JSON Pointer. If the receiver does not represent a
    /// container then an error is thrown.
    ///
    /// - Parameters:
    ///   - component: A single component of a JSON Pointer to evaluate.
    /// - Returns: The referenced value.
    private func value(for component: String) throws -> JSONElement {
        switch self {
        case .object(let dictionary), .mutableObject(let dictionary as NSDictionary):
            guard let property = dictionary[component] else {
                throw JSONError.referencesNonexistentValue
            }
            let child = try JSONElement(any: property)
            return child

        case .array(let array) where component == "-",
             .mutableArray(let array as NSArray) where component == "-":
            guard let lastElement = array.lastObject else {
                throw JSONError.referencesNonexistentValue
            }
            let child = try JSONElement(any: lastElement)
            return child

        case .array(let array), .mutableArray(let array as NSArray):
            guard
                JSONPointer.isValidArrayIndex(component),
                let index = Int(component),
                0..<array.count ~= index else {
                    throw JSONError.referencesNonexistentValue
            }
            let element = array[index]
            let child = try JSONElement(any: element)
            return child

        case .string, .number, .null:
            throw JSONError.referencesNonexistentValue
        }
    }

    /// Set a value in the receiver json element. This method is only valid for mutable
    /// container json elements.
    ///
    /// - Parameters:
    ///   - value: The new value to set.
    ///   - component: The component of a json pointer.
    ///   - replace: Only affects arrays. If true the given value replaces any previous
    ///     value identified by component. Otherwise the give value is inserted into the
    ///     array and all existing values following the insertion point are shifted up.
    private mutating func setValue(_ value: JSONElement, component: String, replace: Bool) throws {
        switch self {
        case .mutableObject(let dictionary):
            dictionary[component] = value.rawValue
        case .mutableArray(let array):
            if component == "-" {
                if replace && array.count > 0 {
                    array.replaceObject(at: array.count - 1, with: value.rawValue)
                } else {
                    array.add(value.rawValue)
                }
            } else {
                guard
                    JSONPointer.isValidArrayIndex(component),
                    let index = Int(component),
                    0...array.count ~= index else {
                        throw JSONError.referencesNonexistentValue
                }
                if replace {
                    array.replaceObject(at: index, with: value.rawValue)
                } else {
                    array.insert(value.rawValue, at: index)
                }
            }
        default:
            assertionFailure("Receiver is not a mutable container")
            break
        }
    }

    /// Remove a value from the receiver json element. This method is only valid for
    /// mutable container json elements. The given component of a json pointer identifies
    /// the value to remove. If the value referenced by the component does not exist
    /// then an error is thrown.
    ///
    /// - Parameters:
    ///   - component: The component of a json pointer the identifies the value to remove.
    /// - Throws: JSONError.referencesNonexistentValue if the value is not found.
    private mutating func removeValue(component: String) throws {
        switch self {
        case .mutableObject(let dictionary):
            guard dictionary[component] != nil else {
                throw JSONError.referencesNonexistentValue
            }
            dictionary.removeObject(forKey: component)
        case .mutableArray(let array):
            if component == "-" {
                guard array.count > 0 else {
                    throw JSONError.referencesNonexistentValue
                }
                array.removeLastObject()
            } else {
                guard
                    JSONPointer.isValidArrayIndex(component),
                    let index = Int(component),
                    0..<array.count ~= index else {
                        throw JSONError.referencesNonexistentValue

                }
                array.removeObject(at: index)
            }
        default:
            assertionFailure("Receiver is not a mutable container")
            break
        }
    }

    /// Evaluates a JSON Pointer relative to the receiver JSON Element.
    ///
    /// - Parameters:
    ///   - pointer: The JSON Pointer to evaluate.
    /// - Returns: The JSON Element pointed to by the JSON Pointer
    public func evaluate(pointer: JSONPointer) throws -> JSONElement {
        return try pointer.reduce(self, { return try $0.value(for: $1) })
    }

    // MARK:- Apply JSON Patch Operation Methods

    /// Adds the value to the JSON structure pointed to by the JSON Pointer.
    ///
    /// - Parameters:
    ///   - value: A JSON Element holding a reference to the value to add.
    ///   - pointer: A JSON Pointer of the location to insert the value.
    public mutating func add(value: JSONElement, to pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = value
            return
        }

        var parentElement = try makePathMutable(parent)
        try parentElement.setValue(value, component: pointer.lastComponent!, replace: false)
    }

    /// Removes a value from a JSON structure pointed to by the JSON Pointer.
    ///
    /// - Parameters:
    ///   - pointer: A JSON Pointer of the location of the value to remove.
    public mutating func remove(at pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = .null
            return
        }

        var parentElement = try makePathMutable(parent)
        try parentElement.removeValue(component: pointer.lastComponent!)
    }

    /// Replaces a value at the location pointed to by the JSON Pointer with
    /// the given value. There must be an existing value to replace for this
    /// operation to be successful.
    ///
    /// - Parameters:
    ///   - value: A JSON Element holding a reference to the value to add.
    ///   - pointer: A JSON Pointer of the location of the value to replace.
    public mutating func replace(value: JSONElement, to pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = value
            return
        }

        var parentElement = try makePathMutable(parent)
        _ = try parentElement.value(for: pointer.lastComponent!)
        try parentElement.setValue(value, component: pointer.lastComponent!, replace: true)
    }

    /// Moves a value at the from location to a new location within the JSON Structure.
    ///
    /// - Parameters:
    ///   - from: The location of the JSON element to move.
    ///   - to: The location to move the value to.
    public mutating func move(from: JSONPointer, to: JSONPointer) throws {
        guard let toParent = to.parent else {
            self = try evaluate(pointer: from)
            return
        }

        guard let fromParent = from.parent else {
            throw JSONError.referencesNonexistentValue
        }

        var fromParentElement = try  makePathMutable(fromParent)
        let value = try fromParentElement.value(for: from.lastComponent!)
        try fromParentElement.removeValue(component: from.lastComponent!)

        var toParentElement = try makePathMutable(toParent)
        try toParentElement.setValue(value, component: to.lastComponent!, replace: false)
    }

    /// Copies a JSON element within the JSON structure to a new location.
    ///
    /// - Parameters:
    ///   - from: The location of the value to copy.
    ///   - to: The location to insert the new value.
    public mutating func copy(from: JSONPointer, to: JSONPointer) throws {
        guard let toParent = to.parent else {
            self = try evaluate(pointer: from)
            return
        }

        guard let fromParent = from.parent else {
            throw JSONError.referencesNonexistentValue
        }

        let fromParentElement = try makePathMutable(fromParent)
        var toParentElement = try makePathMutable(toParent)
        let value = try fromParentElement.value(for: from.lastComponent!)
        let valueCopy = value.copy()
        try toParentElement.setValue(valueCopy, component: to.lastComponent!, replace: false)
    }

    /// Tests a value within the JSON structure against the given value.
    ///
    /// - Parameters:
    ///   - value: The expected value.
    ///   - pointer: The location of the value to test.
    public func test(value: JSONElement, at pointer: JSONPointer) throws {
        do {
            let found = try evaluate(pointer: pointer)
            if found != value {
                throw JSONError.patchTestFailed(path: pointer.string,
                                                expected: value.rawValue,
                                                found: found.rawValue)
            }
        } catch {
            throw JSONError.patchTestFailed(path: pointer.string,
                                            expected: value.rawValue,
                                            found: nil)
        }
    }

    /// Applys a json-patch operation to the reciever.
    ///
    /// - Parameters:
    ///   - operation: The operation to apply.
    public mutating func apply(_ operation: JSONPatch.Operation) throws {
        switch operation {
        case let .add(path, value):
            try add(value: value, to: path)
        case let .remove(path):
            try remove(at: path)
        case let .replace(path, value):
            try replace(value: value, to: path)
        case let .move(from, path):
            try move(from: from, to: path)
        case let .copy(from, path):
            try copy(from: from, to: path)
        case let .test(path, value):
            try test(value: value, at: path)
        }
    }

    /// Applys a json-patch to the the reciever. If a relative path is given then
    /// the json pointer is evaluated on the reciever, and then the patch is applied
    /// on the evaluted element.
    ///
    /// - Parameters:
    ///   - patch: The json-patch to be applied.
    ///   - path:  If present then the patch is applied to the child element at the path.
    public mutating func apply(patch: JSONPatch, relativeTo path: JSONPointer? = nil) throws {
        if let path = path, let parent = path.parent {
            var parentElement = try makePathMutable(parent)
            var relativeRoot = try parentElement.value(for: path.lastComponent!)
            try relativeRoot.apply(patch: patch)
            try parentElement.setValue(relativeRoot, component: path.lastComponent!, replace: true)
        } else {
            for operation in patch.operations {
                try apply(operation)
            }
        }
    }

}

extension JSONElement: Equatable {

    /// Tests if two JSON Elements are structurally.
    ///
    /// - Parameters:
    ///   - lhs: Left-hand side of the equality test.
    ///   - rhs: Right-hand side of the equality test.
    /// - Returns: true if lhs and rhs are structurally, otherwise false.
    public static func == (lhs: JSONElement, rhs: JSONElement) -> Bool {
        guard let lobj = lhs.rawValue as? JSONEquatable else {
            return false
        }
        return lobj.isJSONEquals(to: rhs)
    }

    /// Determines if two json elements have equivalent types.
    ///
    /// - Parameters:
    ///   - lhs: Left-hand side of the equivalent type test.
    ///   - rhs: Right-hand side of the equivalent type test.
    /// - Returns: true if lhs and rhs are of equivalent types, otherwise false.
    public static func equivalentTypes(lhs: JSONElement, rhs: JSONElement) -> Bool {
        switch (lhs, rhs) {
        case (.object, .object),
             (.object, .mutableObject),
             (.mutableObject, .object),
             (.mutableObject, .mutableObject),
             (.array, .array),
             (.array, .mutableArray),
             (.mutableArray, .array),
             (.mutableArray, .mutableArray),
             (.string, .string),
             (.null, .null):
            return true
        case (.number(let numl), .number(let numr)):
            return numl.isBoolean == numr.isBoolean
        default:
            return false
        }
    }

}

extension JSONSerialization {

    /// Parse JSON data to a JSOE Element. This wraps the jsonObject(with:options:) method
    /// however the resuting Any type is wrapped in a JSONElement type.
    ///
    /// - Parameters:
    ///   - data: The JSON data to parse. See jsonObject(with:options:) for supported encodings.
    ///   - options: The reading options. See jsonObject(with:options:) for supported options.
    /// - Returns: The JSON Element representing the top-level element of the json document.
    public static func jsonElement(with data: Data, options: ReadingOptions) throws -> JSONElement {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: options)
        return try JSONElement(any: jsonObject)
    }

    /// Generate JSON data from a JSONElement using JSONSerialization. This method supports
    /// top-level fragments (root elements that are not containers).
    ///
    /// - Parameters:
    ///   - jsonElement: The top-level json element to generate data for.
    ///   - options: The wripting options for generating the json data.
    /// - Returns: A UTF-8 represention of the json document with the jsonElement as the root.
    public static func data(with jsonElement: JSONElement, options: WritingOptions = []) throws -> Data {
        // JSONSerialization only supports writing top-level containers.
        switch jsonElement {
        case let .object(obj as NSObject),
             let .mutableObject(obj as NSObject),
             let .array(obj as NSObject),
             let .mutableArray(obj as NSObject):
            return try JSONSerialization.data(withJSONObject: obj, options: options)
        default:
            // If the element is not a container then wrap the element in an array and the
            // return the sub-sequence of the result that represents the original element.
            let array = [jsonElement.rawValue]
            // We ignore the passed in writing options for this case, as it only effects
            // containers and could cause indexes to shift.
            let data = try JSONSerialization.data(withJSONObject: array, options: [])
            guard let arrayEndRange = data.range(of: Data("]".utf8),
                                                 options: [.backwards],
                                                 in: nil) else {
                                                    throw JSONError.invalidObjectType
            }
            let subdata = data.subdata(in: data.index(after: data.startIndex)..<arrayEndRange.startIndex)
            return subdata
        }
    }

}
