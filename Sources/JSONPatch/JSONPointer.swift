//
//  JSONPointer.swift
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

/// A JSON Pointer implementation, based on RFC 6901.
/// https://tools.ietf.org/html/rfc6901
public struct JSONPointer {
    /// A string representation of the json-pointer.
    public let string: String

    /// An array of the unescaped components of the json-pointer.
    public let components: [String]

    /// An internal initalizer for the JSONPointer to force public access to use init(string:).
    private init(string: String, components: [String]) {
        self.string = string
        self.components = components
    }
}

extension JSONPointer {

    /// A JSON Pointer to the container of the element of the reciever, or nil if the reciever
    /// references the root element of the whole JSON document.
    public var parent: JSONPointer? {
        guard
            components.count > 0,
            let index = string.lastIndex(of: "/") else {
            return nil
        }
        guard string != "/" else {
            return JSONPointer(string: "", components: [])
        }

        if index == string.startIndex {
            return JSONPointer(string: "/", components: [""])
        } else {
            return try? JSONPointer(string: String(string[..<index]))
        }
    }

    public var isWholeDocument: Bool {
        return components.isEmpty
    }

    public var fragment: String? {
        guard let s = string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else {
            return nil
        }
        return "#\(s)"
    }

    /// Initializer for JSONPointer
    public init(string: String) throws {
        guard !string.isEmpty else {
            self.init(string: string, components: [])
            return
        }
        guard !string.hasPrefix("#") else {
            let index = string.index(after: string.startIndex)
            guard let unescaped = string[index...].removingPercentEncoding else {
                throw JSONError.invalidPointerSyntax
            }
            try self.init(string: unescaped)
            return
        }
        guard string.hasPrefix("/") else {
            throw JSONError.invalidPointerSyntax
        }

        let escapedComponents = string.components(separatedBy: "/").dropFirst()
        let unescapedComponents = escapedComponents.map(JSONPointer.unescape)
        self.init(string: string, components: unescapedComponents)
    }

    /// Unescapes the escape sequence within the string.
    ///
    /// - Parameters:
    ///   - escaped: The escaped string.
    /// - Returns: The unescaped string.
    public static func unescape(_ escaped: String) -> String {
        var value = escaped
        value = value.replacingOccurrences(of: "~1", with: "/")
        value = value.replacingOccurrences(of: "~0", with: "~")
        return value
    }

    public static func escape(_ unescaped: String) -> String {
        var value = unescaped
        value = value.replacingOccurrences(of: "~", with: "~0")
        value = value.replacingOccurrences(of: "/", with: "~1")
        return value
    }

}

extension JSONPointer {
    private static let arrayIndexPattern: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "^(?:-|0|(?:[1-9][0-9]*))$", options: [])
    }()

    static func isValidArrayIndex(_ component: String) -> Bool {
        let match = arrayIndexPattern.firstMatch(in: component,
                                                 options: [.anchored],
                                                 range: NSRange(location: 0, length: component.utf16.count))
        return match != nil
    }
}

extension JSONPointer: CustomDebugStringConvertible {

    public var debugDescription: String {
        return "JSONPointer(string: \"\(string)\")"
    }

}

extension JSONPointer: Equatable {

    public static func == (lhs: JSONPointer, rhs: JSONPointer) -> Bool {
        return lhs.string == rhs.string
    }

}
