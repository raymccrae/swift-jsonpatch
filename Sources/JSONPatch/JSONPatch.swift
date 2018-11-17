//
//  JSONPatch.swift
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

    public convenience init(jsonArray: NSArray) throws {
        var operations: [JSONPatch.Operation] = []
        for (index, element) in (jsonArray as Array).enumerated() {
            guard let obj = element as? NSDictionary else {
                throw JSONError.invalidPatchFormat
            }
            let operation = try JSONPatch.Operation(jsonObject: obj, index: index)
            operations.append(operation)
        }
        self.init(operations: operations)
    }

    public func apply(to jsonObject: Any) throws -> Any {
        return try operations.reduce(into: try JSONElement(any: jsonObject)) { try $0.apply($1) }.rawValue
    }

    public func apply(to data: Data,
                      readingOptions: JSONSerialization.ReadingOptions = [.mutableContainers],
                      writingOptions: JSONSerialization.WritingOptions = []) throws -> Data {
        let jsonObject = try JSONSerialization.jsonObject(with: data,
                                                          options: readingOptions)
        let transformedObject = try apply(to: jsonObject)
        let transformedData = try JSONSerialization.data(withJSONObject: transformedObject,
                                                         options: writingOptions)
        return transformedData
    }

}

extension JSONPatch.Operation {

    private static func val(_ jsonObject: NSDictionary,
                            _ op: String,
                            _ field: String,
                            _ index: Int) throws -> String {
        guard let value = jsonObject[field] as? String else {
            throw JSONError.missingRequiredPatchField(op: op, index: index, field: field)
        }
        return value
    }

    /// Initialize a json-operation from a JSON Object representation.
    /// If the operation is not recogized or is missing a required field
    /// then nil is returned.
    public init(jsonObject: NSDictionary, index: Int = 0) throws {
        guard let op = jsonObject["op"] as? String else {
            throw JSONError.missingRequiredPatchField(op: "", index: index, field: "op")
        }

        switch op {
        case "add":
            let path = try JSONPatch.Operation.val(jsonObject, "add", "path", index)
            let value = try JSONPatch.Operation.val(jsonObject, "add", "value", index)
            let pointer = try JSONPointer(string: path)
            self = .add(path: pointer, value: value)
        case "remove":
            let path = try JSONPatch.Operation.val(jsonObject, "remove", "path", index)
            let pointer = try JSONPointer(string: path)
            self = .remove(path: pointer)
        case "replace":
            let path = try JSONPatch.Operation.val(jsonObject, "replace", "path", index)
            let value = try JSONPatch.Operation.val(jsonObject, "replace", "value", index)
            let pointer = try JSONPointer(string: path)
            self = .replace(path: pointer, value: value)
        case "move":
            let from = try JSONPatch.Operation.val(jsonObject, "move", "from", index)
            let path = try JSONPatch.Operation.val(jsonObject, "move", "path", index)
            let fpointer = try JSONPointer(string: from)
            let ppointer = try JSONPointer(string: path)
            self = .move(from: fpointer, path: ppointer)
        case "copy":
            let from = try JSONPatch.Operation.val(jsonObject, "copy", "from", index)
            let path = try JSONPatch.Operation.val(jsonObject, "copy", "path", index)
            let fpointer = try JSONPointer(string: from)
            let ppointer = try JSONPointer(string: path)
            self = .copy(from: fpointer, path: ppointer)
        case "test":
            let path = try JSONPatch.Operation.val(jsonObject, "test", "path", index)
            let value = try JSONPatch.Operation.val(jsonObject, "test", "value", index)
            let pointer = try JSONPointer(string: path)
            self = .test(path: pointer, value: value)
        default:
            throw JSONError.unknownPatchOperation
        }
    }
}

extension JSONPatch.Operation: Equatable {

    public static func == (lhs: JSONPatch.Operation, rhs: JSONPatch.Operation) -> Bool {
        switch (lhs, rhs) {
        case let (.add(lpath, lvalue as NSObject), .add(rpath, rvalue as NSObject)),
             let (.replace(lpath, lvalue as NSObject), .replace(rpath, rvalue as NSObject)),
             let (.test(lpath, lvalue as NSObject), .test(rpath, rvalue as NSObject)):
            return lpath == rpath && lvalue.isEqual(rvalue)
        case let (.remove(lpath), .remove(rpath)):
            return lpath == rpath
        case let (.move(lfrom, lpath), .move(rfrom, rpath)),
             let (.copy(lfrom, lpath), .copy(rfrom, rpath)):
            return lfrom == rfrom && lpath == rpath
        default:
            return false
        }
    }

}

extension JSONPatch: Equatable {

    public static func == (lhs: JSONPatch, rhs: JSONPatch) -> Bool {
        return lhs.operations == rhs.operations
    }

}
