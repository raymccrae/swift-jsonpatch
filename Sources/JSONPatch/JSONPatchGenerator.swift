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

    // Internal helpers are exercised directly by collision and size tests.
    struct CopySource {
        let path: JSONPointer
        let value: JSONElement
        let spelling: String
        let encodedBytes: Int

        init(path: JSONPointer, value: JSONElement) {
            self.path = path
            self.value = value
            spelling = path.string
            encodedBytes = CopyCost.stringSize(spelling, limit: Int.max - 1)
        }

        static func precedes(_ a: Self, _ b: Self) -> Bool {
            if a.encodedBytes != b.encodedBytes { return a.encodedBytes < b.encodedBytes }
            return a.spelling.unicodeScalars.lexicographicallyPrecedes(b.spelling.unicodeScalars) { $0.value < $1.value }
        }
    }

    struct CopyIndex {
        private var buckets: [Int: [CopySource]] = [:]

        // Sources are ordered once by the lookup. Injection permits deliberate
        // collisions in tests without weakening or exposing a public hash option.
        init(orderedSources: [CopySource], fingerprint: (JSONElement) -> Int? = copyFingerprint) {
            for source in orderedSources {
                if let key = fingerprint(source.value) { buckets[key, default: []].append(source) }
            }
        }

        func count(for key: Int) -> Int { buckets[key]?.count ?? 0 }

        func source(for value: JSONElement, fingerprint: Int) -> CopySource? {
            // A fingerprint is only a filter. Exact equality is required even
            // when the bucket has just one entry.
            buckets[fingerprint]?.first { valuesEqual($0.value, value) }
        }
    }

    struct CopyLookup {
        private var sources: [CopySource]
        private var ordered = false
        private var index: CopyIndex?
        private var indexUseful = true
        private(set) var linearComparisons = 0
        private(set) var builtIndex = false

        init(sources: [CopySource]) { self.sources = sources }

        mutating func source(for value: JSONElement, remainingQueries: Int) -> CopySource? {
            if !ordered { sources.sort(by: CopySource.precedes); ordered = true }
            // Cheap hits and small searches stay linear. A single expensive miss
            // cannot amortize an index; require work already observed and at least
            // two queries still to serve, including the current query.
            if index == nil, indexUseful, sources.count >= 16,
               linearComparisons >= 64, remainingQueries >= 2 {
                index = CopyIndex(orderedSources: sources)
                builtIndex = true
            }
            if let index, let key = copyFingerprint(value) {
                if index.count(for: key) < max(2, sources.count / 2) {
                    return index.source(for: value, fingerprint: key)
                }
                // Bounded fingerprints may be deliberately coarse. Avoid paying
                // to hash every future query when the filter is unselective.
                self.index = nil
                indexUseful = false
            }
            for source in sources {
                linearComparisons += 1
                if valuesEqual(source.value, value) { return source }
            }
            return nil
        }
    }

    // Bound extra traversal: sample string prefixes and small containers. Large
    // containers contribute type and count; collisions always get exact checks.
    // Numbers deliberately share a tag: Foundation numeric equality spans integer,
    // floating-point and decimal representations, so hashing their spellings (or
    // converting to Double) could exclude an equal value. Booleans are separate.
    static func copyFingerprint(_ value: JSONElement) -> Int? {
        fingerprint(value, depth: 2)
    }

    private static func fingerprint(_ value: JSONElement, depth: Int) -> Int? {
        var hash = Hasher()
        switch value {
        case .null: hash.combine(0)
        case .number(let number):
            if number.isBoolean { hash.combine(1); hash.combine(number.boolValue) }
            else { hash.combine(2) }
        case .string(let string):
            hash.combine(3)
            hash.combine(string.length)
            for scalar in (string as String).unicodeScalars.prefix(32) { hash.combine(scalar.value) }
        case .array(let array), .mutableArray(let array as NSArray):
            hash.combine(4)
            hash.combine(array.count)
            if depth > 0 {
                for index in 0..<min(8, array.count) {
                    guard let item = try? JSONElement(any: array.jsonObject(at: index)),
                          let key = fingerprint(item, depth: depth - 1) else { return nil }
                    hash.combine(key)
                }
            }
        case .object(let object), .mutableObject(let object as NSDictionary):
            hash.combine(5)
            hash.combine(object.count)
            if depth > 0, object.count <= 8 {
                guard let keys = object.allKeys as? [String] else { return nil }
                var sum: UInt = 0
                var xor: UInt = 0
                for key in keys {
                    guard let raw = object.jsonObject(forKey: key as NSString),
                          let item = try? JSONElement(any: raw),
                          let child = fingerprint(item, depth: depth - 1) else { return nil }
                    var entry = Hasher()
                    for scalar in key.unicodeScalars { entry.combine(scalar.value) }
                    entry.combine(child)
                    let bits = UInt(bitPattern: entry.finalize())
                    sum &+= bits
                    xor ^= bits
                }
                // Commutative combination preserves object-order independence.
                hash.combine(sum)
                hash.combine(xor)
            }
        }
        return hash.finalize()
    }

    enum CopyCost {
        // Default compact JSONSerialization escapes '/', quotes and controls.
        // The add/copy metadata has the same byte count: the extra byte in
        // "copy" cancels the shorter "from" key. Destination cost also cancels.
        static func stringSize(_ string: String, limit: Int) -> Int {
            var count = 2 // quotes
            if count > limit { return limit + 1 }
            for scalar in string.unicodeScalars {
                let bytes: Int
                switch scalar.value {
                case 0x22, 0x5C, 0x2F, 8, 9, 10, 12, 13: bytes = 2
                case 0..<0x20: bytes = 6
                case 0..<0x80: bytes = 1
                case 0..<0x800: bytes = 2
                case 0..<0x10000: bytes = 3
                default: bytes = 4
                }
                if bytes > limit - count { return limit + 1 }
                count += bytes
            }
            return count
        }

        static func integerSize(_ number: NSNumber) -> Int? {
            var magnitude: UInt64
            var count = 1
            switch String(cString: number.objCType) {
            case "c", "s", "i", "l", "q":
                let value = number.int64Value
                magnitude = value.magnitude
                if value < 0 { count += 1 }
            case "C", "S", "I", "L", "Q": magnitude = number.uint64Value
            default: return nil
            }
            while magnitude >= 10 { magnitude /= 10; count += 1 }
            return count
        }

        // Saturate at limit + 1: proving a large literal exceeds a short source
        // path need not serialize or walk the whole value. nil keeps the literal
        // when a Foundation value cannot be measured safely.
        static func literalSize(_ value: JSONElement, limit: Int) -> Int? {
            switch value {
            case .null: return min(4, limit + 1)
            case .string(let string): return stringSize(string as String, limit: limit)
            case .number(let number):
                let count: Int
                if number.isBoolean { count = number.boolValue ? 4 : 5 }
                else {
                    if let integerBytes = integerSize(number) { count = integerBytes }
                    else {
                        // Float/decimal formatting belongs to Foundation. This
                        // fallback is measured; it is not used for fingerprints.
                        guard let data = try? JSONSerialization.data(withJSONObject: number, options: [.fragmentsAllowed]) else { return nil }
                        count = data.count
                    }
                }
                return min(count, limit + 1)
            case .array(let array), .mutableArray(let array as NSArray):
                if limit < 2 || (array.count > 0 && array.count > (limit - 1) / 2) { return limit + 1 }
                var count = 2 + max(0, array.count - 1)
                for index in 0..<array.count {
                    guard let item = try? JSONElement(any: array.jsonObject(at: index)),
                          let bytes = literalSize(item, limit: limit - count) else { return nil }
                    count += bytes
                    if count > limit { return limit + 1 }
                }
                return count
            case .object(let object), .mutableObject(let object as NSDictionary):
                if limit < 2 || (object.count > 0 && object.count > (limit - 1) / 5) { return limit + 1 }
                guard let keys = object.allKeys as? [String] else { return nil }
                var count = 2 + max(0, object.count - 1)
                for key in keys {
                    count += stringSize(key, limit: limit - count) + 1 // colon
                    if count > limit { return limit + 1 }
                    guard let raw = object.jsonObject(forKey: key as NSString),
                          let item = try? JSONElement(any: raw),
                          let bytes = literalSize(item, limit: limit - count) else { return nil }
                    count += bytes
                    if count > limit { return limit + 1 }
                }
                return count
            }
        }
    }

    private var copyQueryCount = 0
    private var unchanged: [CopySource] = []
    private var shortestSourceBytes = Int.max
    private var numberSizes: [ObjectIdentifier: Int] = [:]
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
        for (_, value) in additions {
            if mayBenefitFromCopy(value) { copyQueryCount += 1 }
        }
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
        for value in additions {
            if mayBenefitFromCopy(value) { copyQueryCount += 1 }
        }
        return .array(removals: removals, additions: additions, children: children)
    }

    private mutating func plan(pointer: JSONPointer, comparison: Comparison) {
        switch comparison {
        case .unchanged(let value):
            if copyQueryCount > 0 {
                let source = CopySource(path: pointer, value: value)
                shortestSourceBytes = min(shortestSourceBytes, source.encodedBytes)
                unchanged.append(source)
            }
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
            for (key, child) in children where copyQueryCount > 0 || !child.isUnchanged {
                plan(pointer: pointer.appended(withComponent: key.name), comparison: child)
            }
        case .array(let removals, let additions, let children):
            // Only remove the tail and append; stable source indices do not move.
            // Array matching or reordered edits must revisit this invariant.
            for index in removals.reversed() {
                operations.append(.remove(path: pointer.appended(withIndex: index)))
            }
            for (index, child) in children.enumerated() where copyQueryCount > 0 || !child.isUnchanged {
                plan(pointer: pointer.appended(withIndex: index), comparison: child)
            }
            if !additions.isEmpty {
                let appendPointer = pointer.appended(withComponent: "-")
                for value in additions { operations.append(.add(path: appendPointer, value: value)) }
            }
        }
    }

    private func mayBenefitFromCopy(_ value: JSONElement) -> Bool {
        if case .number(let number) = value {
            if number.isBoolean { return !number.boolValue } // false is five bytes.
            if let bytes = CopyCost.integerSize(number) { return bytes > 4 }
            // Delay floating/decimal formatting until a source is available.
            return true
        }
        return CopyCost.literalSize(value, limit: 4).map { $0 > 4 } ?? false
    }

    private mutating func literalSize(_ value: JSONElement, limit: Int) -> Int? {
        if case .number(let number) = value {
            if number.isBoolean { return min(number.boolValue ? 4 : 5, limit + 1) }
            if let bytes = CopyCost.integerSize(number) { return min(bytes, limit + 1) }
            // NSNumber is immutable. Planned additions retain these objects until
            // resolution; all query costs are collected before any add is replaced.
            let identity = ObjectIdentifier(number)
            if let bytes = numberSizes[identity] { return min(bytes, limit + 1) }
            guard let bytes = CopyCost.literalSize(value, limit: Int.max - 1) else { return nil }
            numberSizes[identity] = bytes
            return min(bytes, limit + 1)
        }
        return CopyCost.literalSize(value, limit: limit)
    }

    private mutating func resolveCopies() {
        guard copyQueryCount > 0, !unchanged.isEmpty else { return }
        // No whole-document source is collected when there are edits; the
        // shortest possible quoted non-root source is "\\/", four bytes.
        var queries: [Int] = []
        for index in operations.indices {
            if case .add(_, let value) = operations[index],
               let size = literalSize(value, limit: shortestSourceBytes), size > shortestSourceBytes {
                queries.append(index)
            }
        }
        guard !queries.isEmpty else { return }
        var lookup = CopyLookup(sources: unchanged)
        unchanged = []
        for (position, index) in queries.enumerated() {
            guard case .add(let path, let value) = operations[index],
                  let source = lookup.source(for: value, remainingQueries: queries.count - position) else { continue }
            if source.encodedBytes != shortestSourceBytes {
                guard let size = literalSize(value, limit: source.encodedBytes), size > source.encodedBytes else { continue }
            }
            // Resolution replaces the add in place. Only maximal unchanged
            // sources participate, so the stage 2 sequential-path invariant holds.
            operations[index] = .copy(from: source.path, path: path)
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
