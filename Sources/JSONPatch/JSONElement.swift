//
//  JSONElement.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation

/// JSON Element holds a reference an element of the parsed JSON structure.
enum JSONElement {
    case object(value: NSDictionary)
    case mutableObject(value: NSMutableDictionary)
    case array(value: NSArray)
    case mutableArray(value: NSMutableArray)
    case string(value: NSString)
    case number(value: NSNumber)
    case null
}

extension JSONElement {

    /// The raw value of the underlying JSON representation.
    var rawValue: Any {
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

    /// Indicates if the receiver is a mutable container (dictionary or array).
    var isMutable: Bool {
        switch self {
        case .mutableObject, .mutableArray:
            return true
        case .object, .array, .string, .number, .null:
            return false
        }
    }

    init(any: Any) throws {
        switch any {
        case is NSMutableDictionary:
            self = .mutableObject(value: any as! NSMutableDictionary)
        case is NSDictionary:
            self = .object(value: any as! NSDictionary)
        case is NSMutableArray:
            self = .mutableArray(value: any as! NSMutableArray)
        case is NSArray:
            self = .array(value: any as! NSArray)
        case is NSString:
            self = .string(value: any as! NSString)
        case is NSNumber:
            self = .number(value: any as! NSNumber)
        case is NSNull:
            self = .null
        default:
            throw JSONError.invalidObjectType
        }
    }

    private func copy() -> JSONElement {
        let obj = rawValue as! NSObject
        let objCopy: Any
        if isMutable {
            objCopy = obj.mutableCopy()
        } else {
            objCopy = obj.copy()
        }
        return try! JSONElement(any: objCopy)
    }

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

    private mutating func makePathMutable(_ pointer: JSONPointer) throws -> JSONElement {
        if !self.isMutable {
            self.makeMutable()
        }

        guard pointer.string != "/" else {
            return self
        }

        var element = self
        for component in pointer.components {
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
            break
        }
    }

    private mutating func removeValue(component: String) throws {
        switch self {
        case .mutableObject(let dictionary):
            dictionary.removeObject(forKey: component)
        case .mutableArray(let array):
            if component == "-" {
                array.removeLastObject()
            } else {
                guard
                    let index = Int(component),
                    0..<array.count ~= index else {
                        throw JSONError.referencesNonexistentValue

                }
                array.removeObject(at: index)
            }
        default:
            break
        }
    }

    /// Evaluates a JSON Pointer relative to the receiver JSON Element.
    ///
    /// - Parameters:
    ///   - pointer: The JSON Pointer to evaluate.
    /// - Returns: The JSON Element pointed to by the JSON Pointer
    func evaluate(pointer: JSONPointer) throws -> JSONElement {
        return try pointer.components.reduce(self, { return try $0.value(for: $1) })
    }

    mutating func add(value: JSONElement, to pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = value
            return
        }

        var parentElement = try makePathMutable(parent)
        try parentElement.setValue(value, component: pointer.components.last!, replace: false)
    }

    mutating func remove(at pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = .null
            return
        }

        var parentElement = try makePathMutable(parent)
        try parentElement.removeValue(component: pointer.components.last!)
    }

    mutating func replace(value: JSONElement, to pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = value
            return
        }

        var parentElement = try makePathMutable(parent)
        _ = try parentElement.value(for: pointer.components.last!)
        try parentElement.setValue(value, component: pointer.components.last!, replace: true)
    }

    mutating func move(from: JSONPointer, to: JSONPointer) throws {
        guard let toParent = to.parent else {
            self = try evaluate(pointer: from)
            return
        }

        guard let fromParent = from.parent else {
            throw JSONError.referencesNonexistentValue
        }

        var fromParentElement = try  makePathMutable(fromParent)
        var toParentElement = try makePathMutable(toParent)
        let value = try fromParentElement.value(for: from.components.last!)
        try fromParentElement.removeValue(component: from.components.last!)
        try toParentElement.setValue(value, component: to.components.last!, replace: false)
    }

    mutating func copy(from: JSONPointer, to: JSONPointer) throws {
        guard let toParent = to.parent else {
            self = try evaluate(pointer: from)
            return
        }

        guard let fromParent = from.parent else {
            throw JSONError.referencesNonexistentValue
        }

        var fromParentElement = try  makePathMutable(fromParent)
        var toParentElement = try makePathMutable(toParent)
        let value = try fromParentElement.value(for: from.components.last!)
        let valueCopy = value.copy()
        try toParentElement.setValue(valueCopy, component: to.components.last!, replace: false)
    }

    func test(value: JSONElement, at pointer: JSONPointer) throws {
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

    mutating func apply(_ operation: JSONPatch.Operation) throws {
        switch operation {
        case let .add(path, value):
            try add(value: try JSONElement(any: value), to: path)
        case let .remove(path):
            try remove(at: path)
        case let .replace(path, value):
            try replace(value: try JSONElement(any: value), to: path)
        case let .move(from, path):
            try move(from: from, to: path)
        case let .copy(from, path):
            try copy(from: from, to: path)
        case let .test(path, value):
            try test(value: try JSONElement(any: value), at: path)
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
    static func == (lhs: JSONElement, rhs: JSONElement) -> Bool {
        guard
            let lobj = lhs.rawValue as? NSObject,
            let robj = rhs.rawValue as? NSObject else {
                return false
        }
        return lobj.isEqual(robj)
//        switch (lhs, rhs) {
//        case (.object(let lobj), .object(let robj)),
//             (.object(let lobj), .mutableObject(let robj as NSDictionary)),
//             (.mutableObject(let lobj as NSDictionary), .object(let robj)),
//             (.mutableObject(let lobj as NSDictionary), .mutableObject(let robj as NSDictionary)):
//            return lobj.isEqual(robj)
//        case (.array(let larr), .array(let rarr)),
//             (.array(let larr), .mutableArray(let rarr as NSArray)),
//             (.mutableArray(let larr as NSArray), .array(let rarr)),
//             (.mutableArray(let larr as NSArray), .mutableArray(let rarr as NSArray)):
//            return larr.isEqual(rarr)
//        case (.string(let lstr), .string(let rstr)):
//            return lstr.isEqual(rstr)
//        case (.number(let lnum), .number(let rnum)):
//            return lnum.isEqual(to: rnum)
//        case (.null, .null):
//            return true
//        default:
//            return false
//        }
    }

}
