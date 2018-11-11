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
    public let string: String
    public let components: [String]
}

extension JSONPointer {

    var parent: JSONPointer? {
        guard
            components.count > 1,
            let index = string.lastIndex(of: "/") else {
            return nil
        }
        return try? JSONPointer(string: String(string[..<index]))
    }

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

    static func unescape(_ escaped: String) -> String {
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
