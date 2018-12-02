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

    /// An array of the unescaped components of the json-pointer.
    private let components: ArraySlice<String>

    /// An internal initalizer for the JSONPointer to force public access to use init(string:).
    private init(components: ArraySlice<String>) {
        self.components = components
    }

}

extension JSONPointer {

    /// A json-pointer that represents the whole json document.
    static let wholeDocument: JSONPointer = JSONPointer(components: [])

    /// A string representation of the json-pointer.
    public var string: String {
        guard !components.isEmpty else {
            return ""
        }
        return "/" + components.map(JSONPointer.escape).joined(separator: "/")
    }

    /// A JSON Pointer to the container of the element of the reciever, or nil if the reciever
    /// references the root element of the whole JSON document.
    public var parent: JSONPointer? {
        guard !components.isEmpty else {
            return nil
        }
        return JSONPointer(components: components.dropLast())
    }

    /// The path component of the receiver.
    public var lastComponent: String? {
        return components.last
    }

    /// Determines if receiver represents the whole document.
    public var isWholeDocument: Bool {
        return components.isEmpty
    }

    /// Returns a URI Fragment Identifier representation. See Section 6 of RFC 6901.
    public var fragment: String? {
        guard let s = string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else {
            return nil
        }
        return "#\(s)"
    }

    /// Initializer for JSONPointer
    public init(string: String) throws {
        guard !string.isEmpty else {
            self.init(components: [])
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
        self.init(components: ArraySlice(unescapedComponents))
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

    /// Escapes the characters required for the RFC 6901 standard.
    ///
    /// - Parameters:
    ///   - unescaped: The unescaped string.
    /// - Returns: The escaped string.
    public static func escape(_ unescaped: String) -> String {
        var value = unescaped
        value = value.replacingOccurrences(of: "~", with: "~0")
        value = value.replacingOccurrences(of: "/", with: "~1")
        return value
    }

    /// Creates a new json-pointer based on the reciever with the given component appended.
    ///
    /// - Parameters:
    ///   - component: A non-escaped path component.
    /// - Returns: A json-pointer with the given component appended.
    func appended(withComponent component: String) -> JSONPointer {
        return JSONPointer(components: ArraySlice(components + [component]))
    }

    /// Creates a new json-pointer based on the reciever with the given index appended.
    ///
    /// - Parameters:
    ///   - index: A path index.
    /// - Returns: A json-pointer with the given component appended.
    func appended(withIndex index: Int) -> JSONPointer {
        return JSONPointer(components: ArraySlice(components + [String(index)]))
    }

}

extension JSONPointer {
    private static let arrayIndexPattern: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "^(?:-|0|(?:[1-9][0-9]*))$", options: [])
    }()

    /// Determines if the given path component represents a valid array index.
    ///
    /// - Parameters:
    ///   - component: A path component.
    /// - Returns: true if the given path component is a valid array index, otherwise false.
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
    /// Returns a Boolean value indicating whether two json-pointer are equal.
    ///
    /// - Parameters:
    ///   - lhs: Left-hand side of the equality test.
    ///   - rhs: Right-hand side of the equality test.
    /// - Returns: true is the lhs is equal to the rhs.
    public static func == (lhs: JSONPointer, rhs: JSONPointer) -> Bool {
        return lhs.components == rhs.components
    }
}

extension JSONPointer: Hashable {
    public var hashValue: Int {
        return components.hashValue
    }
}

extension JSONPointer: Collection {
    public var startIndex: Int {
        return components.startIndex
    }

    public var endIndex: Int {
        return components.endIndex
    }

    public func index(after i: Int) -> Int {
        return i + 1
    }

    public subscript(index: Int) -> String {
        return components[index]
    }
}
