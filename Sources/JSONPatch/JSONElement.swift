//
//  JSONElement.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation

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

    var isMutable: Bool {
        switch self {
        case .mutableObject, .mutableArray:
            return true
        case .object, .array, .string, .number, .null:
            return false
        }
    }

    public init?(any: Any) {
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
            return nil
        }
    }

    mutating func makeMutable() {
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

    mutating func makePathMutable(_ pointer: JSONPointer) throws -> JSONElement {

        if !self.isMutable {
            self.makeMutable()
        }

        var element = self
        for component in pointer.components {
            var child = try element.value(for: component)
            if !child.isMutable {
                child.makeMutable()
                try element.setValue(child, component: component)
            }
            element = child
        }

        return element
    }

    private func value(for component: String) throws -> JSONElement {
        switch self {
        case .object(let dictionary), .mutableObject(let dictionary as NSDictionary):
            guard
                let property = dictionary[component],
                let child = JSONElement(any: property) else {
                    throw JSONError.referencesNonexistentValue
            }
            return child

        case .array(let array) where component == "-",
             .mutableArray(let array as NSArray) where component == "-":
            guard
                let lastElement = array.lastObject,
                let child = JSONElement(any: lastElement) else {
                    throw JSONError.referencesNonexistentValue
            }
            return child

        case .array(let array), .mutableArray(let array as NSArray):
            guard
                let index = Int(component),
                0..<array.count ~= index else {
                    throw JSONError.referencesNonexistentValue

            }
            let element = array[index]
            guard let child = JSONElement(any: element) else { throw JSONError.referencesNonexistentValue }
            return child

        case .string, .number, .null:
            throw JSONError.referencesNonexistentValue
        }
    }

    mutating func setValue(_ value: JSONElement, component: String) throws {
        switch self {
        case .mutableObject(let dictionary):
            dictionary[component] = value.rawValue
        case .mutableArray(let array):
            if component == "-" {
                array.add(value.rawValue)
            } else {
                guard
                    let index = Int(component),
                    0..<array.count ~= index else {
                        throw JSONError.referencesNonexistentValue

                }
                array.insert(value.rawValue, at: index)
            }
        default:
            break
        }
    }

    public func evaluate(pointer: JSONPointer) throws -> JSONElement {
        var json: JSONElement = self
        for component in pointer.components {
            switch json {
            case .object(let value):
                guard
                    let property = value[component],
                    let nextJSON = JSONElement(any: property) else {
                        throw JSONError.referencesNonexistentValue
                }
                json = nextJSON

            case .array(let value) where component == "-":
                guard
                    let lastElement = value.lastObject,
                    let nextJSON = JSONElement(any: lastElement) else {
                        throw JSONError.referencesNonexistentValue
                }
                json = nextJSON

            case .array(let value):
                guard let index = Int(component) else { throw JSONError.referencesNonexistentValue }
                let element = value[index]
                guard let nextJSON = JSONElement(any: element) else { throw JSONError.referencesNonexistentValue }
                json = nextJSON

            default:
                throw JSONError.referencesNonexistentValue
            }
        }
        return json
    }

    public mutating func add(value: JSONElement, to pointer: JSONPointer) throws {
        guard let parent = pointer.parent else {
            self = value
            return
        }

        var parentElement = try makePathMutable(parent)
        try parentElement.setValue(value, component: pointer.components.last!)
    }

}

extension JSONElement: Equatable {

    public static func == (lhs: JSONElement, rhs: JSONElement) -> Bool {
        switch (lhs, rhs) {
        case (.object(let lobj), .object(let robj)):
            return lobj.isEqual(robj)
        case (.array(let larr), .array(let rarr)):
            return larr.isEqual(rarr)
        case (.string(let lstr), .string(let rstr)):
            return lstr.isEqual(rstr)
        case (.number(let lnum), .number(let rnum)):
            return lnum.isEqual(to: rnum)
        case (.null, .null):
            return true
        default:
            return false
        }
    }

}
