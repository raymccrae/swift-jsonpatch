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
                guard let valueA = a.jsonObject(forKey: key.name as NSString),
                      let valueB = b.jsonObject(forKey: key.name as NSString),
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
                guard let elementA = try? JSONElement(any: a.jsonObject(at: index)),
                      let elementB = try? JSONElement(any: b.jsonObject(at: index)),
                      valuesEqual(elementA, elementB) else { return false }
            }
            return true
        default:
            return lhs == rhs
        }
    }

    // An equal subtree is kept as one source, matching the original candidate
    // policy. Paths are constructed only after comparison, when edits are known.
    private enum Comparison {
        case unchanged(JSONElement)
        case replace(JSONElement)
        case object(removals: [ObjectKey], additions: [(ObjectKey, JSONElement)],
                    children: [(ObjectKey, Comparison)])
        case array(removals: Range<Int>, additions: [JSONElement], children: [Comparison])

        var isUnchanged: Bool {
            if case .unchanged = self { return true }
            return false
        }
    }

    private var hasAdditions = false
    private var unchanged: [JSONPointer: JSONElement] = [:]
    private var operations: [JSONPatch.Operation] = []

    static func generatePatch(source: JSONElement, target: JSONElement) throws -> [JSONPatch.Operation] {
        var generator = JSONPatchGenerator()
        let comparison = try generator.compare(source: source, target: target)
        guard !comparison.isUnchanged else { return [] }
        generator.plan(pointer: .wholeDocument, comparison: comparison)
        generator.resolveCopies()
        return generator.operations
    }

    // Compare each corresponding pair once. Container equality, key sets, and
    // child conversions are reused by the edit plan rather than recomputed by
    // separate unchanged-value and diff traversals. Everything lives in this call.
    private mutating func compare(source: JSONElement, target: JSONElement) throws -> Comparison {
        switch (source, target) {
        case (.object(let a), .object(let b)),
             (.object(let a), .mutableObject(let b as NSDictionary)),
             (.mutableObject(let a as NSDictionary), .object(let b)),
             (.mutableObject(let a as NSDictionary), .mutableObject(let b as NSDictionary)):
            if a === b { return .unchanged(source) }
            return try compareObjects(a, b, source: source)
        case (.array(let a), .array(let b)),
             (.array(let a), .mutableArray(let b as NSArray)),
             (.mutableArray(let a as NSArray), .array(let b)),
             (.mutableArray(let a as NSArray), .mutableArray(let b as NSArray)):
            if a === b { return .unchanged(source) }
            return try compareArrays(a, b, source: source)
        default:
            return source == target ? .unchanged(source) : .replace(target)
        }
    }

    private mutating func compareObjects(_ a: NSDictionary, _ b: NSDictionary,
                                         source: JSONElement) throws -> Comparison {
        guard let keysA = Self.objectKeys(a), let keysB = Self.objectKeys(b) else {
            return .unchanged(source)
        }
        let common = keysA.intersection(keysB)
        var equal = keysA == keysB
        var children: [(ObjectKey, Comparison)] = []
        children.reserveCapacity(common.count)
        for key in common {
            guard let valueA = a.jsonObject(forKey: key.name as NSString),
                  let valueB = b.jsonObject(forKey: key.name as NSString) else { continue }
            let child = try compare(source: JSONElement(any: valueA), target: JSONElement(any: valueB))
            equal = equal && child.isUnchanged
            children.append((key, child))
        }
        if equal { return .unchanged(source) }

        var removals: [ObjectKey] = []
        for key in keysA.subtracting(keysB) {
            guard let value = a.jsonObject(forKey: key.name as NSString) else { continue }
            // Preserve validation of removed values accepted by the public wrapper.
            _ = try JSONElement(any: value)
            removals.append(key)
        }
        var additions: [(ObjectKey, JSONElement)] = []
        for key in keysB.subtracting(keysA) {
            guard let value = b.jsonObject(forKey: key.name as NSString) else { continue }
            additions.append((key, try JSONElement(any: value)))
        }
        hasAdditions = hasAdditions || !additions.isEmpty
        return .object(removals: removals, additions: additions, children: children)
    }

    private mutating func compareArrays(_ a: NSArray, _ b: NSArray,
                                        source: JSONElement) throws -> Comparison {
        let count = min(a.count, b.count)
        var equal = a.count == b.count
        var children: [Comparison] = []
        children.reserveCapacity(count)
        for index in 0..<count {
            let child = try compare(source: JSONElement(any: a.jsonObject(at: index)),
                                    target: JSONElement(any: b.jsonObject(at: index)))
            equal = equal && child.isUnchanged
            children.append(child)
        }
        if equal { return .unchanged(source) }

        let removals = count..<a.count
        for index in removals { _ = try JSONElement(any: a.jsonObject(at: index)) }
        var additions: [JSONElement] = []
        if a.count < b.count {
            additions.reserveCapacity(b.count - a.count)
            for index in a.count..<b.count {
                additions.append(try JSONElement(any: b.jsonObject(at: index)))
            }
        }
        hasAdditions = hasAdditions || !additions.isEmpty
        return .array(removals: removals, additions: additions, children: children)
    }

    private mutating func plan(pointer: JSONPointer, comparison: Comparison) {
        switch comparison {
        case .unchanged(let value):
            if hasAdditions { unchanged[pointer] = value }
        case .replace(let value):
            operations.append(.replace(path: pointer, value: value))
        case .object(let removals, let additions, let children):
            // Keep the original execution order: removals, additions, then edits
            // to common properties. Copy lookup is deferred, not the operation.
            for key in removals {
                operations.append(.remove(path: pointer.appended(withComponent: key.name)))
            }
            for (key, value) in additions {
                operations.append(.add(path: pointer.appended(withComponent: key.name), value: value))
            }
            for (key, child) in children where hasAdditions || !child.isUnchanged {
                plan(pointer: pointer.appended(withComponent: key.name), comparison: child)
            }
        case .array(let removals, let additions, let children):
            // Only remove the tail and append; stable source indices do not move.
            // Array matching or reordered edits must revisit this invariant.
            for index in removals.reversed() {
                operations.append(.remove(path: pointer.appended(withIndex: index)))
            }
            for (index, child) in children.enumerated() where hasAdditions || !child.isUnchanged {
                plan(pointer: pointer.appended(withIndex: index), comparison: child)
            }
            if !additions.isEmpty {
                let appendPointer = pointer.appended(withComponent: "-")
                for value in additions { operations.append(.add(path: appendPointer, value: value)) }
            }
        }
    }

    private mutating func resolveCopies() {
        guard hasAdditions else { return }
        // All maximal unchanged sources, including ones encountered after an
        // addition, are now known. Replacing an add in place preserves execution
        // order and does not expose newly added values as copy sources.
        for index in operations.indices {
            if case .add(let path, let value) = operations[index],
               let from = findUnchangedValue(value: value) {
                operations[index] = .copy(from: from, path: path)
            }
        }
    }

    private func findUnchangedValue(value: JSONElement) -> JSONPointer? {
        for (pointer, old) in unchanged where Self.valuesEqual(value, old) {
            return pointer
        }
        return nil
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
