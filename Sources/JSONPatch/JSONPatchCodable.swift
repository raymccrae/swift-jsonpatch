//
//  JSONPatchCodable.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 01/12/2018.
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

extension JSONPointer: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(string: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

extension JSONElement: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value: value as NSString)
        } else if let value = try? container.decode(Bool.self) {
            self = .number(value: value as NSNumber)
        } else if let value = try? container.decode(Int.self) {
            self = .number(value: value as NSNumber)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value: value as NSNumber)
        } else if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([JSONElement].self) {
            let array = value.map { $0.rawValue }
            self = .array(value: array as NSArray)
        } else if let keyedContainer = try? decoder.container(keyedBy: NSDictionaryCodingKey.self) {
            let keys = keyedContainer.allKeys
            let dict = NSMutableDictionary()
            for key in keys {
                let value = try keyedContainer.decode(JSONElement.self, forKey: key)
                dict[key.stringValue] = value.rawValue
            }
            self = .mutableObject(value: dict)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value as String)
        case .number(let value):
            try container.encodeNSNumber(value)
        case .null:
            try container.encodeNil()
        case .array(let array), .mutableArray(let array as NSArray):
            let elements = try array.map { try JSONElement(any: $0) }
            try container.encode(elements)
        case .object(let dict), .mutableObject(let dict as NSDictionary):
            var keyContainer = encoder.container(keyedBy: NSDictionaryCodingKey.self)
            try keyContainer.encodeNSDictionary(dict)
        }
    }
}

extension JSONPatch.Operation: Codable {
    enum CodingKeys: String, CodingKey {
        case op
        case path
        case value
        case from
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(String.self, forKey: .op)
        switch op {
        case "add":
            let path = try container.decode(JSONPointer.self, forKey: .path)
            let value = try container.decode(JSONElement.self, forKey: .value)
            self = .add(path: path, value: value)
        case "remove":
            let path = try container.decode(JSONPointer.self, forKey: .path)
            self = .remove(path: path)
        case "replace":
            let path = try container.decode(JSONPointer.self, forKey: .path)
            let value = try container.decode(JSONElement.self, forKey: .value)
            self = .replace(path: path, value: value)
        case "move":
            let from = try container.decode(JSONPointer.self, forKey: .from)
            let path = try container.decode(JSONPointer.self, forKey: .path)
            self = .move(from: from, path: path)
        case "copy":
            let from = try container.decode(JSONPointer.self, forKey: .from)
            let path = try container.decode(JSONPointer.self, forKey: .path)
            self = .copy(from: from, path: path)
        case "test":
            let path = try container.decode(JSONPointer.self, forKey: .path)
            let value = try container.decode(JSONElement.self, forKey: .value)
            self = .test(path: path, value: value)
        default:
            throw JSONError.unknownPatchOperation
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .add(path, value):
            try container.encode("add", forKey: .op)
            try container.encode(path, forKey: .path)
            try container.encode(value, forKey: .value)
        case let .remove(path):
            try container.encode("remove", forKey: .op)
            try container.encode(path, forKey: .path)
        case let .replace(path, value):
            try container.encode("replace", forKey: .op)
            try container.encode(path, forKey: .path)
            try container.encode(value, forKey: .value)
        case let .move(from, path):
            try container.encode("move", forKey: .op)
            try container.encode(path, forKey: .path)
            try container.encode(from, forKey: .from)
        case let .copy(from, path):
            try container.encode("copy", forKey: .op)
            try container.encode(path, forKey: .path)
            try container.encode(from, forKey: .from)
        case let .test(path, value):
            try container.encode("test", forKey: .op)
            try container.encode(path, forKey: .path)
            try container.encode(value, forKey: .value)
        }
    }
}

extension SingleValueEncodingContainer {

    fileprivate mutating func encodeNSNumber(_ value: NSNumber) throws {
        switch CFNumberGetType(value) {
        case .charType:
            try encode(value.boolValue)
        case .cgFloatType, .doubleType, .float64Type:
            try encode(value.doubleValue)
        case .floatType, .float32Type:
            try encode(value.floatValue)
        default:
            try encode(value.int64Value)
        }
    }
}

extension KeyedEncodingContainer where Key == NSDictionaryCodingKey {

    fileprivate mutating func encodeNSDictionary(_ value: NSDictionary) throws {
        var encodingError: Error? = nil
        value.enumerateKeysAndObjects { (key, value, stop) in
            do {
                guard
                    let keyString = key as? String,
                    let codingKey = NSDictionaryCodingKey(stringValue: keyString)
                    else {
                        assertionFailure()
                        return
                }
                let element = try JSONElement(any: value)
                try encode(element, forKey: codingKey)
            } catch {
                encodingError = error
                stop.pointee = true
            }
        }
        if let error = encodingError {
            throw error
        }
    }
}

fileprivate struct NSDictionaryCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = ""
        self.intValue = intValue
    }
}
