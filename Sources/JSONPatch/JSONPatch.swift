//
//  JSONPatch.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation

public class JSONPatch {

    public enum Operation {
        case add(path: JSONPointer, value: Any)
        case remove(path: JSONPointer)
        case replace(path: JSONPointer, value: Any)
        case move(from: JSONPointer, path: JSONPointer)
        case copy(from: JSONPointer, path: JSONPointer)
        case test(path: JSONPointer, value: Any)
    }

    public let operations: [JSONPatch.Operation]

    public init(operations: [JSONPatch.Operation]) {
        self.operations = operations
    }

    public func apply(to jsonObject: Any) throws -> Any {
        var json = try JSONElement(any: jsonObject)
        for operation in operations {
            try json.apply(operation)
        }
        return json.rawValue
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
