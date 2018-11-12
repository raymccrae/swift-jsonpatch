//
//  JSONPointer.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
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
    init(string: String, components: [String]) {
        self.string = string
        self.components = components
    }
}

extension JSONPointer {

    /// A JSON Pointer to the container of the element of the reciever, or nil if the reciever
    /// references the root element of the whole JSON document.
    var parent: JSONPointer? {
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

    /// Initializer for JSONPointer
    public init(string: String) throws {
        guard !string.isEmpty else {
            self.init(string: string, components: [])
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
