//
//  JSONPatchGenerator.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 30/11/2018.
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

struct JSONPatchGenerator {

    // Swift String equality normalizes Unicode; JSON property names do not.
    private struct ObjectKey: Hashable {
        let name: String

        static func == (lhs: Self, rhs: Self) -> Bool {
            JSONPointer.tokensEqual(lhs.name, rhs.name)
        }

        func hash(into hasher: inout Hasher) {
            for scalar in name.unicodeScalars {
                hasher.combine(scalar.value)
            }
        }
    }

    private static func objectKeys(_ dictionary: NSDictionary) -> Set<ObjectKey>? {
        guard let keys = dictionary.allKeys as? [String] else { return nil }
        return Set(keys.map { ObjectKey(name: $0) })
    }

    // Use the same exact property identity for early returns and copy candidates
    // as for object diffs, including objects nested inside arrays.
    private static func valuesEqual(_ lhs: JSONElement, _ rhs: JSONElement) -> Bool {
        switch (lhs, rhs) {
        case (.object(let a), .object(let b)),
             (.object(let a), .mutableObject(let b as NSDictionary)),
             (.mutableObject(let a as NSDictionary), .object(let b)),
             (.mutableObject(let a as NSDictionary), .mutableObject(let b as NSDictionary)):
            guard let keysA = objectKeys(a), let keysB = objectKeys(b), keysA == keysB else {
                return false
            }
            for key in keysA {
                guard let valueA = a.object(forKey: key.name as NSString),
                      let valueB = b.object(forKey: key.name as NSString),
                      let elementA = try? JSONElement(any: valueA),
                      let elementB = try? JSONElement(any: valueB),
                      valuesEqual(elementA, elementB) else { return false }
            }
            return true
        case (.array(let a), .array(let b)),
             (.array(let a), .mutableArray(let b as NSArray)),
             (.mutableArray(let a as NSArray), .array(let b)),
             (.mutableArray(let a as NSArray), .mutableArray(let b as NSArray)):
            guard a.count == b.count else { return false }
            for index in 0..<a.count {
                guard let elementA = try? JSONElement(any: a[index]),
                      let elementB = try? JSONElement(any: b[index]),
                      valuesEqual(elementA, elementB) else { return false }
            }
            return true
        default:
            return lhs == rhs
        }
    }

    fileprivate enum Operation {
        case add(path: JSONPointer, value: JSONElement)
        case remove(path: JSONPointer, value: JSONElement)
        case replace(path: JSONPointer, old: JSONElement, value: JSONElement)
        case copy(from: JSONPointer, path: JSONPointer, value: JSONElement)
    }

    private var unchanged: [JSONPointer: JSONElement] = [:]
    private var operations: [Operation] = []
    private var patchOperations: [JSONPatch.Operation] {
        return operations.map(JSONPatch.Operation.init)
    }

    static func generatePatch(source: JSONElement, target: JSONElement) throws -> [JSONPatch.Operation] {
        var generator = JSONPatchGenerator()
        try generator.computeUnchanged(pointer: JSONPointer.wholeDocument, a: source, b: target)
        try generator.generateDiffs(pointer: JSONPointer.wholeDocument, source: source, target: target)
        return generator.patchOperations
    }

    private mutating func computeUnchanged(pointer: JSONPointer, a: JSONElement, b: JSONElement) throws {
        guard !Self.valuesEqual(a, b) else {
            unchanged[pointer] = a
            return
        }

        switch (a, b) {
        case (.object(let dictA), .object(let dictB)),
             (.object(let dictA), .mutableObject(let dictB as NSDictionary)),
             (.mutableObject(let dictA as NSDictionary), .object(let dictB)),
             (.mutableObject(let dictA as NSDictionary), .mutableObject(let dictB as NSDictionary)):
            try computeObjectUnchanged(pointer: pointer, a: dictA, b: dictB)

        case (.array(let arrayA), .array(let arrayB)),
             (.array(let arrayA), .mutableArray(let arrayB as NSArray)),
             (.mutableArray(let arrayA as NSArray), .array(let arrayB)),
             (.mutableArray(let arrayA as NSArray), .mutableArray(let arrayB as NSArray)):
            try computeArrayUnchanged(pointer: pointer, a: arrayA, b: arrayB)

        default:
            break
        }
    }

    private mutating func computeObjectUnchanged(pointer: JSONPointer,
                                                 a: NSDictionary,
                                                 b: NSDictionary) throws {
        guard let keys = Self.objectKeys(a), let otherKeys = Self.objectKeys(b) else {
            return
        }

        for key in keys.intersection(otherKeys) {
            guard let valueA = a.object(forKey: key.name as NSString),
                  let valueB = b.object(forKey: key.name as NSString) else {
                continue
            }
            try computeUnchanged(pointer: pointer.appended(withComponent: key.name),
                                 a: try JSONElement(any: valueA),
                                 b: try JSONElement(any: valueB))
        }
    }

    private mutating func computeArrayUnchanged(pointer: JSONPointer,
                                                a: NSArray,
                                                b: NSArray) throws {
        let count = min(a.count, b.count)
        for index in 0..<count {
            try computeUnchanged(pointer: pointer.appended(withIndex: index),
                                 a: try JSONElement(any: a[index]),
                                 b: try JSONElement(any: b[index]))
        }
    }

    private mutating func generateDiffs(pointer: JSONPointer,
                                        source: JSONElement,
                                        target: JSONElement) throws {
        guard !Self.valuesEqual(source, target) else {
            return
        }

        guard JSONElement.equivalentTypes(lhs: source, rhs: target) else {
            replace(path: pointer, old: source, value: target)
            return
        }

        guard source.isContainer else {
            replace(path: pointer, old: source, value: target)
            return
        }

        switch (source, target) {
        case (.object(let dictA), .object(let dictB)),
             (.object(let dictA), .mutableObject(let dictB as NSDictionary)),
             (.mutableObject(let dictA as NSDictionary), .object(let dictB)),
             (.mutableObject(let dictA as NSDictionary), .mutableObject(let dictB as NSDictionary)):
            try generateObjectDiffs(pointer: pointer, source: dictA, target: dictB)

        case (.array(let arrayA), .array(let arrayB)),
             (.array(let arrayA), .mutableArray(let arrayB as NSArray)),
             (.mutableArray(let arrayA as NSArray), .array(let arrayB)),
             (.mutableArray(let arrayA as NSArray), .mutableArray(let arrayB as NSArray)):
            try generateArrayDiffs(pointer: pointer, source: arrayA, target: arrayB)

        default:
            break
        }
    }

    private mutating func generateObjectDiffs(pointer: JSONPointer,
                                              source: NSDictionary,
                                              target: NSDictionary) throws {
        guard
            let sourceKeySet = Self.objectKeys(source),
            let targetKeySet = Self.objectKeys(target) else {
                return
        }

        for key in sourceKeySet.subtracting(targetKeySet) {
            guard let value = source.object(forKey: key.name as NSString) else { continue }
            remove(path: pointer.appended(withComponent: key.name),
                   value: try JSONElement(any: value))
        }

        for key in targetKeySet.subtracting(sourceKeySet) {
            guard let value = target.object(forKey: key.name as NSString) else { continue }
            add(path: pointer.appended(withComponent: key.name),
                value: try JSONElement(any: value))
        }

        for key in sourceKeySet.intersection(targetKeySet) {
            guard let sourceValue = source.object(forKey: key.name as NSString),
                  let targetValue = target.object(forKey: key.name as NSString) else {
                continue
            }
            try generateDiffs(pointer: pointer.appended(withComponent: key.name),
                              source: try JSONElement(any: sourceValue),
                              target: try JSONElement(any: targetValue))
        }
    }

    private mutating func generateArrayDiffs(pointer: JSONPointer,
                                             source: NSArray,
                                             target: NSArray) throws {
        if source.count > target.count {
            // target is smaller than source, remove end elements.
            for index in (target.count..<source.count).reversed() {
                remove(path: pointer.appended(withIndex: index),
                       value: try JSONElement(any: source[index]))
            }
        }

        let count = min(source.count, target.count)
        for index in 0..<count {
            try generateDiffs(pointer: pointer.appended(withIndex: index),
                              source: try JSONElement(any: source[index]),
                              target: try JSONElement(any: target[index]))
        }

        if source.count < target.count {
            let appendPointer = pointer.appended(withComponent: "-")
            for index in source.count..<target.count {
                add(path: appendPointer,
                    value: try JSONElement(any: target[index]))
            }
        }
    }

    private mutating func replace(path: JSONPointer, old: JSONElement, value: JSONElement) {
        operations.append(.replace(path: path, old: old, value: value))
    }

    private mutating func remove(path: JSONPointer, value: JSONElement) {
        operations.append(.remove(path: path, value: value))
    }

    private mutating func add(path: JSONPointer, value: JSONElement) {
        // Keep earlier removals in place: deferring one until a later move changes
        // the array indices used by intervening operations and subsequent moves.
        if let oldPath = findUnchangedValue(value: value) {
            operations.append(.copy(from: oldPath, path: path, value: value))
        } else {
            operations.append(.add(path: path, value: value))
        }
    }

    private func findUnchangedValue(value: JSONElement) -> JSONPointer? {
        for (pointer, old) in unchanged where Self.valuesEqual(value, old) {
            return pointer
        }
        return nil
    }

}

extension JSONPatch.Operation {
    fileprivate init(_ value: JSONPatchGenerator.Operation) {
        switch value {
        case let .add(path, value):
            self = .add(path: path, value: value)
        case let .remove(path, _):
            self = .remove(path: path)
        case let .copy(from, path, _):
            self = .copy(from: from, path: path)
        case let .replace(path, _, value):
            self = .replace(path: path, value: value)
        }
    }
}

extension JSONPatch {

    /// Initializes a JSONPatch instance with all json-patch operations required to transform the source
    /// json document into the target json document.
    ///
    /// - Parameters:
    ///   - source: The source json document.
    ///   - target: The target json document.
    public convenience init(source: JSONElement, target: JSONElement) throws {
        self.init(operations: try JSONPatchGenerator.generatePatch(source: source, target: target))
    }

    /// Initialize a JSONPatch instance with all json-patch operations required to transform the source
    /// json document into the target json document.
    ///
    /// - Parameters:
    ///   - source: The source json document as data.
    ///   - target: The target json document as data.
    ///   - options: The JSONSerialization options for reading the source and target data.
    public convenience init(source: Data, target: Data, options: JSONSerialization.ReadingOptions = []) throws {
        let sourceJson = try JSONSerialization.jsonElement(with: source, options: options)
        let targetJson = try JSONSerialization.jsonElement(with: target, options: options)
        try self.init(source: sourceJson, target: targetJson)
    }
}
