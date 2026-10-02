//
//  JSONError.swift
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

public enum JSONError: Error {
    case invalidObjectType
    case invalidPointerSyntax
    case invalidPatchFormat
    case referencesNonexistentValue
    case unknownPatchOperation
    case missingRequiredPatchField(op: String, index: Int, field: String)
    /// Immutable JSON snapshots; a missing path has no `found` value, while JSON null does.
    case patchTestFailed(path: String, expected: Value, found: Value?)
}

extension JSONError {
    /// A JSON value captured as UTF-8 data, safe to transfer between actors.
    public struct Value: Sendable {
        /// The captured value as UTF-8 JSON, including top-level fragments.
        public let data: Data

        /// Captures a JSON-compatible value, including a top-level scalar or null.
        /// - Throws: `JSONError.invalidObjectType` if the value cannot be represented as JSON.
        public init(jsonObject: Any) throws {
            // Wrapping the value validates fragments too, before invoking the writer.
            guard JSONSerialization.isValidJSONObject([jsonObject]) else {
                throw JSONError.invalidObjectType
            }
            do {
                data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed])
            } catch {
                throw JSONError.invalidObjectType
            }
        }

        /// Decodes a fresh Foundation representation of the snapshot.
        public func jsonObject() throws -> Any {
            try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
    }
}

extension JSONError: Equatable {
    public static func ==(lhs: JSONError, rhs: JSONError) -> Bool {
        switch lhs {
        case .invalidObjectType:
            if case .invalidObjectType = rhs {
                return true
            }
            
        case .invalidPointerSyntax:
            if case .invalidPointerSyntax = rhs {
                return true
            }
            
        case .invalidPatchFormat:
            if case .invalidPatchFormat = rhs {
                return true
            }
            
        case .referencesNonexistentValue:
            if case .referencesNonexistentValue = rhs {
                return true
            }
            
        case .unknownPatchOperation:
            if case .unknownPatchOperation = rhs {
                return true
            }
            
        case .missingRequiredPatchField(let op1, let index1, let field1):
            if case .missingRequiredPatchField(let op2, let index2, let field2) = rhs,
                op1 == op2 && index1 == index2 && field1 == field2 {
                return true
            }
            
        case .patchTestFailed(let path1, _, _):
            if case .patchTestFailed(let path2, _, _) = rhs,
                path1 == path2 {
                return true
            }
        }
        
        return false
    }
}
