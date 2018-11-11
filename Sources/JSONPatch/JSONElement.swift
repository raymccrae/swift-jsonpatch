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
    case array(value: NSArray)
    case string(value: NSString)
    case number(value: NSNumber)
    case null
}

extension JSONElement {

    public init?(any: Any) {
        switch any {
        case is NSDictionary:
            self = .object(value: any as! NSDictionary)
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
