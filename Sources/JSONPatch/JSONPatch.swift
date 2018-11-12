//
//  JSONPatch.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation

/// Implementation of IETF JSON Patch (RFC6902).
public class JSONPatch {

    /// A representation of the supported operations json-patch.
    /// (see [RFC6902], Section 4)
    public enum Operation {
        case add(path: JSONPointer, value: Any)
        case remove(path: JSONPointer)
        case replace(path: JSONPointer, value: Any)
        case move(from: JSONPointer, path: JSONPointer)
        case copy(from: JSONPointer, path: JSONPointer)
        case test(path: JSONPointer, value: Any)
    }

    /// An array of json-patch operations.
    public let operations: [JSONPatch.Operation]

    public init(operations: [JSONPatch.Operation]) {
        self.operations = operations
    }

    public convenience init(jsonArray: NSArray) {
        let operations = jsonArray.compactMap { (element) -> JSONPatch.Operation? in
            guard let dictionary = element as? NSDictionary else {
                    return nil
            }
            return JSONPatch.Operation(jsonObject: dictionary)
        }
        self.init(operations: operations)
    }

    public func apply(to jsonObject: Any) throws -> Any {
        return try operations.reduce(into: try JSONElement(any: jsonObject)) { try $0.apply($1) }.rawValue
    }

    public func apply(to data: Data, options: JSONSerialization.WritingOptions = []) throws -> Data {
        let jsonObject = try JSONSerialization.jsonObject(with: data,
                                                          options: [.mutableContainers])
        let transformedObject = try apply(to: jsonObject)
        let transformedData = try JSONSerialization.data(withJSONObject: transformedObject,
                                                         options: options)
        return transformedData
    }

}

extension JSONPatch.Operation {
    /// Initialize a json-operation from a JSON Object representation.
    /// If the operation is not recogized or is missing a required field
    /// then nil is returned.
    public init?(jsonObject: NSDictionary) {
        guard let op = jsonObject["op"] as? String else {
            return nil
        }

        switch op {
        case "add":
            guard
                let path = jsonObject["path"] as? String,
                let pointer = try? JSONPointer(string: path),
                let value = jsonObject["value"] else {
                    return nil
            }
            self = .add(path: pointer, value: value)
        case "remove":
            guard
                let path = jsonObject["path"] as? String,
                let pointer = try? JSONPointer(string: path) else {
                    return nil
            }
            self = .remove(path: pointer)
        case "replace":
            guard
                let path = jsonObject["path"] as? String,
                let pointer = try? JSONPointer(string: path),
                let value = jsonObject["value"] else {
                    return nil
            }
            self = .replace(path: pointer, value: value)
        case "move":
            guard
                let from = jsonObject["from"] as? String,
                let fpointer = try? JSONPointer(string: from),
                let path = jsonObject["path"] as? String,
                let ppointer = try? JSONPointer(string: path) else {
                    return nil
            }
            self = .move(from: fpointer, path: ppointer)
        case "copy":
            guard
                let from = jsonObject["from"] as? String,
                let fpointer = try? JSONPointer(string: from),
                let path = jsonObject["path"] as? String,
                let ppointer = try? JSONPointer(string: path) else {
                    return nil
            }
            self = .copy(from: fpointer, path: ppointer)
        case "test":
            guard
                let path = jsonObject["path"] as? String,
                let pointer = try? JSONPointer(string: path),
                let value = jsonObject["value"] else {
                    return nil
            }
            self = .test(path: pointer, value: value)
        default:
            // As per the spec, unrecogized ops should be ignored.
            return nil
        }
    }
}
