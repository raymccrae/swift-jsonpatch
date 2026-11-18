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
        case array(ArrayPlan)

        var isUnchanged: Bool {
            if case .unchanged = self { return true }
            return false
        }

        var isReplacement: Bool {
            if case .replace = self { return true }
            return false
        }
    }

    // Extra sequence-search work is bounded independently of the positional
    // comparison needed to generate a correct fallback patch.
    enum ArrayMatching {
        static let maximumWork = 65_536
        static let maximumDistance = 8

        struct Result {
            let prefix: Int
            let suffix: Int
            let matches: [(source: Int, target: Int)]
            let usedFallback: Bool
            let equalityLimited: Bool
            let work: Int
            let traceEntries: Int
        }

        private struct Budget {
            let limit: Int
            var remaining: Int

            mutating func spend(_ count: Int) -> Bool {
                guard count <= remaining else { return false }
                remaining -= count
                return true
            }

            mutating func equal(_ a: JSONElement, _ b: JSONElement, depth: Int = 0) throws -> Bool? {
                guard spend(1) else { return nil }
                switch (a, b) {
                case (.string(let x), .string(let y)):
                    if x === y { return true }
                    guard x.length == y.length else { return false }
                    guard x.length <= remaining / 2, spend(x.length * 2) else { return nil }
                    return JSONPointer.tokensEqual(x as String, y as String)
                case (.array(let x), .array(let y)),
                     (.array(let x), .mutableArray(let y as NSArray)),
                     (.mutableArray(let x as NSArray), .array(let y)),
                     (.mutableArray(let x as NSArray), .mutableArray(let y as NSArray)):
                    if x === y { return true }
                    guard x.count == y.count else { return false }
                    guard depth < 16, spend(x.count) else { return nil }
                    for index in 0..<x.count {
                        let left = try JSONElement(any: x.jsonObject(at: index))
                        let right = try JSONElement(any: y.jsonObject(at: index))
                        guard let same = try equal(left, right, depth: depth + 1) else { return nil }
                        if !same { return false }
                    }
                    return true
                case (.object(let x), .object(let y)),
                     (.object(let x), .mutableObject(let y as NSDictionary)),
                     (.mutableObject(let x as NSDictionary), .object(let y)),
                     (.mutableObject(let x as NSDictionary), .mutableObject(let y as NSDictionary)):
                    if x === y { return true }
                    guard x.count == y.count else { return false }
                    guard depth < 16, x.count <= 32, spend(x.count) else { return nil }
                    var keys: [String] = []
                    for raw in x.allKeys {
                        guard let key = raw as? NSString else { return nil }
                        guard key.length <= remaining / 2, spend(key.length * 2) else { return nil }
                        keys.append(key as String)
                    }
                    // Mismatch order and budget exhaustion must not depend on
                    // the process's randomized object-key enumeration.
                    func precedes(_ a: String, _ b: String) -> Bool {
                        a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) { $0.value < $1.value }
                    }
                    func valueEqual(_ key: String) throws -> Bool? {
                        guard let left = x.jsonObject(forKey: key as NSString),
                              let right = y.jsonObject(forKey: key as NSString) else { return false }
                        return try equal(JSONElement(any: left), JSONElement(any: right), depth: depth + 1)
                    }
                    // Probe the canonical first key before sorting the rest.
                    // Cheap record mismatches need not pay for a complete sort.
                    if let index = keys.indices.min(by: { precedes(keys[$0], keys[$1]) }) {
                        let first = keys.remove(at: index)
                        guard let same = try valueEqual(first) else { return nil }
                        if !same { return false }
                    }
                    keys.sort(by: precedes)
                    for key in keys {
                        guard let same = try valueEqual(key) else { return nil }
                        if !same { return false }
                    }
                    return true
                default: return a == b
                }
            }
        }

        static func align(_ a: NSArray, _ b: NSArray, workLimit: Int = maximumWork) throws -> Result {
            precondition(workLimit >= 0)
            var budget = Budget(limit: workLimit, remaining: workLimit)
            var prefix = 0
            var suffix = 0
            var trace: [[Int]] = []
            func result(_ matches: [(Int, Int)] = [], fallback: Bool = false, equalityLimited: Bool = false) -> Result {
                Result(prefix: prefix, suffix: suffix, matches: matches, usedFallback: fallback, equalityLimited: equalityLimited,
                       work: budget.limit - budget.remaining,
                       traceEntries: trace.reduce(0) { $0 + $1.count })
            }
            func elements(_ i: Int, _ j: Int) throws -> (JSONElement, JSONElement) {
                (try JSONElement(any: a.jsonObject(at: i)), try JSONElement(any: b.jsonObject(at: j)))
            }
            while prefix < min(a.count, b.count) {
                let (x, y) = try elements(prefix, prefix)
                guard let same = try budget.equal(x, y) else { return result(fallback: true, equalityLimited: true) }
                if !same { break }
                prefix += 1
            }
            while suffix < min(a.count, b.count) - prefix {
                let (x, y) = try elements(a.count - suffix - 1, b.count - suffix - 1)
                guard let same = try budget.equal(x, y) else { return result(fallback: true, equalityLimited: true) }
                if !same { break }
                suffix += 1
            }
            let n = a.count - prefix - suffix
            let m = b.count - prefix - suffix
            if n == 0 || m == 0 || (n == 1 && m == 1) { return result() }
            guard abs(n - m) <= maximumDistance else { return result(fallback: true) }
            let distanceLimit = min(maximumDistance, max(2, (n + m) / 4))
            let offset = distanceLimit + 1
            var frontier = [Int](repeating: 0, count: 2 * distanceLimit + 3)
            // Bounded Myers search. Snapshot at the start of each distance for
            // backtracking; at distance 8 this stores at most 171 integers.
            for distance in 0...distanceLimit {
                trace.append(frontier)
                for diagonal in stride(from: -distance, through: distance, by: 2) {
                    guard budget.spend(1) else { return result(fallback: true, equalityLimited: true) }
                    var x: Int
                    if diagonal == -distance || (diagonal != distance && frontier[offset + diagonal - 1] < frontier[offset + diagonal + 1]) {
                        x = frontier[offset + diagonal + 1]
                    } else { x = frontier[offset + diagonal - 1] + 1 }
                    var y = x - diagonal
                    while x < n && y < m {
                        let (left, right) = try elements(prefix + x, prefix + y)
                        guard let same = try budget.equal(left, right) else { return result(fallback: true, equalityLimited: true) }
                        if !same { break }
                        x += 1
                        y += 1
                    }
                    frontier[offset + diagonal] = x
                    if x >= n && y >= m {
                        var pairs: [(Int, Int)] = []
                        var bx = n
                        var by = m
                        for d in stride(from: distance, through: 1, by: -1) {
                            let previous = trace[d]
                            let k = bx - by
                            let previousK: Int
                            if k == -d || (k != d && previous[offset + k - 1] < previous[offset + k + 1]) {
                                previousK = k + 1
                            } else { previousK = k - 1 }
                            let previousX = previous[offset + previousK]
                            let previousY = previousX - previousK
                            while bx > previousX && by > previousY {
                                pairs.append((prefix + bx - 1, prefix + by - 1))
                                bx -= 1
                                by -= 1
                            }
                            bx = previousX
                            by = previousY
                        }
                        while bx > 0 && by > 0 {
                            pairs.append((prefix + bx - 1, prefix + by - 1))
                            bx -= 1
                            by -= 1
                        }
                        let anchors = Array(pairs.reversed())
                        var old = prefix
                        var new = prefix
                        var edits = 0
                        for anchor in anchors {
                            edits += max(anchor.0 - old, anchor.1 - new)
                            old = anchor.0 + 1
                            new = anchor.1 + 1
                        }
                        edits += max(a.count - suffix - old, b.count - suffix - new)
                        // Reject an alignment that needs more top-level edits
                        // than a positional middle. In particular, a small
                        // reversal must not become many removals and insertions.
                        if edits > max(n, m) { return result(fallback: true) }
                        return result(anchors)
                    }
                }
            }
            return result(fallback: true)
        }
    }

    private enum ArrayPart {
        case keep(source: Range<Int>, target: Int)
        case change(source: Int, target: Int, comparison: Comparison)
        case remove(Range<Int>)
        case insert(index: Int, value: JSONElement, append: Bool)
    }

    private struct ArrayPlan {
        let source: NSArray
        let parts: [ArrayPart]
        // Only original indices before the first shift are safe for the whole
        // operation sequence. A final matching value alone is not sufficient.
        let copySourcePrefix: Int
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
        static func literalSize(_ value: JSONElement, limit: Int, remainingDepth: Int = Int.max) -> Int? {
            switch value {
            case .null: return min(4, limit + 1)
            case .string(let string):
                if remainingDepth != Int.max && (limit < 2 || string.length > limit - 2) { return limit + 1 }
                return stringSize(string as String, limit: limit)
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
                guard remainingDepth > 0 else { return nil }
                if limit < 2 || (array.count > 0 && array.count > (limit - 1) / 2) { return limit + 1 }
                var count = 2 + max(0, array.count - 1)
                for index in 0..<array.count {
                    guard let item = try? JSONElement(any: array.jsonObject(at: index)),
                          let bytes = literalSize(item, limit: limit - count,
                                                  remainingDepth: remainingDepth == Int.max ? Int.max : remainingDepth - 1) else { return nil }
                    count += bytes
                    if count > limit { return limit + 1 }
                }
                return count
            case .object(let object), .mutableObject(let object as NSDictionary):
                guard remainingDepth > 0 else { return nil }
                if limit < 2 || (object.count > 0 && object.count > (limit - 1) / 5) { return limit + 1 }
                if remainingDepth != Int.max {
                    // Bound key bridging before forming a Swift String array.
                    var minimum = 2
                    for raw in object.allKeys {
                        guard let key = raw as? NSString else { return nil }
                        if key.length > limit - minimum { return limit + 1 }
                        minimum += key.length
                    }
                }
                guard let keys = object.allKeys as? [String] else { return nil }
                var count = 2 + max(0, object.count - 1)
                for key in keys {
                    count += stringSize(key, limit: limit - count) + 1 // colon
                    if count > limit { return limit + 1 }
                    guard let raw = object.jsonObject(forKey: key as NSString),
                          let item = try? JSONElement(any: raw),
                          let bytes = literalSize(item, limit: limit - count,
                                                  remainingDepth: remainingDepth == Int.max ? Int.max : remainingDepth - 1) else { return nil }
                    count += bytes
                    if count > limit { return limit + 1 }
                }
                return count
            }
        }
    }

    // Optional whole-document comparison, after copies and structural adaptation.
    // The encoded-byte ceiling bounds traversed literals; depth and operation
    // ceilings also bound shape overhead. Unknown estimates retain the patch.
    enum ReplacementCost {
        static let maximumOperations = 2_048
        static let maximumBytes = 65_536
        static let maximumDepth = 16
        static let maximumPointerDepth = 32

        private static func pointerSize(_ pointer: JSONPointer, limit: Int) -> Int? {
            guard pointer.count <= maximumPointerDepth, limit >= 2 else { return nil }
            var minimum = 2
            for token in pointer {
                let bytes = token.utf8.count
                guard bytes <= limit - minimum else { return nil }
                minimum += bytes
            }
            let bytes = CopyCost.stringSize(pointer.string, limit: limit)
            return bytes <= limit ? bytes : nil
        }

        static func operationSize(_ operation: JSONPatch.Operation, limit: Int) -> Int? {
            let path: JSONPointer
            let from: JSONPointer?
            let value: JSONElement?
            var bytes: Int
            switch operation {
            case .replace(let p, let v): path = p; value = v; from = nil; bytes = 33
            case .add(let p, let v): path = p; value = v; from = nil; bytes = 29
            case .remove(let p): path = p; value = nil; from = nil; bytes = 23
            case .copy(let f, let p), .move(let f, let p): path = p; from = f; value = nil; bytes = 29
            case .test(let p, let v): path = p; value = v; from = nil; bytes = 30
            }
            guard bytes <= limit, let pathBytes = pointerSize(path, limit: limit - bytes) else { return nil }
            bytes += pathBytes
            if let from {
                guard let size = pointerSize(from, limit: limit - bytes) else { return nil }
                bytes += size
            }
            if let value {
                guard let size = CopyCost.literalSize(value, limit: limit - bytes, remainingDepth: maximumDepth) else { return nil }
                bytes += size
            }
            return bytes <= limit ? bytes : nil
        }

        static func prefersReplacement(_ operations: [JSONPatch.Operation], target: JSONElement) -> Bool {
            guard operations.count >= 2, operations.count <= maximumOperations else { return false }
            var old = 1 // array brackets and the first operation's missing comma
            for operation in operations {
                guard old < maximumBytes,
                      let size = operationSize(operation, limit: maximumBytes - old - 1) else { return false }
                old += size + 1
            }
            // [] + replace metadata + quoted empty path = 37 bytes.
            guard old > 37,
                  let size = CopyCost.literalSize(target, limit: old - 38, remainingDepth: maximumDepth) else { return false }
            return size <= old - 38 // Strictly smaller; ties keep the detailed patch.
        }
    }

    private var copyQueryCount = 0
    private var unchanged: [CopySource] = []
    private var shortestSourceBytes = Int.max
    private var numberSizes: [ObjectIdentifier: Int] = [:]
    private var operations: [JSONPatch.Operation] = []

    static func generatePatch(source: JSONElement, target: JSONElement, preferSmallerPatch: Bool = false) throws -> [JSONPatch.Operation] {
        var generator = JSONPatchGenerator()
        let comparison = try generator.compare(source: source, target: target)
        guard !comparison.isUnchanged else { return [] }
        try generator.plan(pointer: .wholeDocument, comparison: comparison)
        generator.resolveCopies()
        if preferSmallerPatch && ReplacementCost.prefersReplacement(generator.operations, target: target) {
            return [.replace(path: .wholeDocument, value: target)]
        }
        return generator.operations
    }

    // A complete set of direct replacements contains every target value once,
    // just as a container replacement does. Values cancel from the size choice:
    // only JSON syntax, operation metadata, and repeated paths differ. There are
    // no planned unchanged descendants to lose as copy sources and no additions
    // whose literals could become smaller copies. Partial edits stay granular.
    static let minimumReplacementChildren = 2

    private static func adapt(_ comparison: Comparison, target: JSONElement) -> Comparison {
        switch comparison {
        case .object(let removals, let additions, let children):
            if removals.isEmpty && additions.isEmpty && children.count >= minimumReplacementChildren &&
                children.allSatisfy({ $0.1.isReplacement }) {
                return .replace(target)
            }
        case .array(let array):
            if array.parts.count >= minimumReplacementChildren && array.parts.allSatisfy({ part in
                if case .change(let source, let target, let child) = part {
                    return source == target && child.isReplacement
                }
                return false
            }) {
                return .replace(target)
            }
        default: break
        }
        return comparison
    }

    // Compare each corresponding pair once. Container equality, key sets, and
    // child conversions are reused by the edit plan rather than recomputed by
    // separate unchanged-value and diff traversals. Everything lives in this call.
    private mutating func compare(source: JSONElement, target: JSONElement, matchArrays: Bool = true) throws -> Comparison {
        switch (source, target) {
        case (.object(let a), .object(let b)),
             (.object(let a), .mutableObject(let b as NSDictionary)),
             (.mutableObject(let a as NSDictionary), .object(let b)),
             (.mutableObject(let a as NSDictionary), .mutableObject(let b as NSDictionary)):
            if a === b { return .unchanged(source) }
            return try Self.adapt(compareObjects(a, b, source: source, matchArrays: matchArrays), target: target)
        case (.array(let a), .array(let b)),
             (.array(let a), .mutableArray(let b as NSArray)),
             (.mutableArray(let a as NSArray), .array(let b)),
             (.mutableArray(let a as NSArray), .mutableArray(let b as NSArray)):
            if a === b { return .unchanged(source) }
            return try Self.adapt(compareArrays(a, b, source: source, matchArrays: matchArrays), target: target)
        default:
            return source == target ? .unchanged(source) : .replace(target)
        }
    }

    private mutating func compareObjects(_ a: NSDictionary, _ b: NSDictionary,
                                         source: JSONElement, matchArrays: Bool) throws -> Comparison {
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
            let child = try compare(source: JSONElement(any: valueA), target: JSONElement(any: valueB), matchArrays: matchArrays)
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
                                        source: JSONElement, matchArrays: Bool) throws -> Comparison {
        // A singleton has no useful sequence alignment to discover. Recurse
        // directly, preserving nested matching without repeatedly probing a deep
        // chain of one-element arrays.
        let search = matchArrays && !(a.count == 1 && b.count == 1)
        let alignment = try search ? ArrayMatching.align(a, b) : ArrayMatching.Result(
            prefix: 0, suffix: 0, matches: [], usedFallback: !matchArrays, equalityLimited: !matchArrays, work: 0, traceEntries: 0)
        if a.count == b.count && alignment.prefix == a.count { return .unchanged(source) }
        var parts: [ArrayPart] = []
        var equal = a.count == b.count
        var safePrefix = a.count
        func keep(_ range: Range<Int>, target: Int) {
            if !range.isEmpty { parts.append(.keep(source: range, target: target)) }
        }
        func changedLength(sourceCount: Int, targetCount: Int, targetStart: Int) {
            if sourceCount != targetCount {
                equal = false
                safePrefix = min(safePrefix, targetStart + min(sourceCount, targetCount))
            }
        }
        // Unmatched runs use recursive positional edits, pairing replacements
        // before emitting excess removals/insertions. This preserves leaf edits
        // instead of turning every substitution into remove + add.
        func gap(_ old: Range<Int>, _ new: Range<Int>) throws {
            changedLength(sourceCount: old.count, targetCount: new.count, targetStart: new.lowerBound)
            let paired = min(old.count, new.count)
            for offset in 0..<paired {
                let i = old.lowerBound + offset
                let j = new.lowerBound + offset
                let child = try compare(source: JSONElement(any: a.jsonObject(at: i)),
                                        target: JSONElement(any: b.jsonObject(at: j)),
                                        matchArrays: matchArrays && !alignment.usedFallback)
                equal = equal && child.isUnchanged
                parts.append(.change(source: i, target: j, comparison: child))
            }
            if old.count > paired {
                let indices = (new.lowerBound + paired)..<(new.lowerBound + old.count)
                parts.append(.remove(indices))
                for index in (old.lowerBound + paired)..<old.upperBound {
                    _ = try JSONElement(any: a.jsonObject(at: index))
                }
            }
            if new.count > paired {
                for index in (new.lowerBound + paired)..<new.upperBound {
                    let value = try JSONElement(any: b.jsonObject(at: index))
                    if mayBenefitFromCopy(value) { copyQueryCount += 1 }
                    parts.append(.insert(index: index, value: value, append: old.upperBound == a.count))
                }
            }
        }
        keep(0..<alignment.prefix, target: 0)
        var oldCursor = alignment.prefix
        var newCursor = alignment.prefix
        var matchIndex = 0
        while matchIndex < alignment.matches.count {
            let first = alignment.matches[matchIndex]
            try gap(oldCursor..<first.source, newCursor..<first.target)
            var length = 1
            while matchIndex + length < alignment.matches.count {
                let next = alignment.matches[matchIndex + length]
                if next.source != first.source + length || next.target != first.target + length { break }
                length += 1
            }
            keep(first.source..<(first.source + length), target: first.target)
            oldCursor = first.source + length
            newCursor = first.target + length
            matchIndex += length
        }
        try gap(oldCursor..<(a.count - alignment.suffix), newCursor..<(b.count - alignment.suffix))
        keep((a.count - alignment.suffix)..<a.count, target: b.count - alignment.suffix)
        if equal { return .unchanged(source) }
        return .array(ArrayPlan(source: a, parts: parts, copySourcePrefix: safePrefix))
    }

    private mutating func plan(pointer: JSONPointer, comparison: Comparison, allowCopySources: Bool = true) throws {
        switch comparison {
        case .unchanged(let value):
            if allowCopySources && copyQueryCount > 0 {
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
            for (key, child) in children where (allowCopySources && copyQueryCount > 0) || !child.isUnchanged {
                try plan(pointer: pointer.appended(withComponent: key.name), comparison: child, allowCopySources: allowCopySources)
            }
        case .array(let array):
            for part in array.parts {
                switch part {
                case .keep(let range, let target):
                    if allowCopySources && copyQueryCount > 0 && range.lowerBound == target {
                        for index in range where index < array.copySourcePrefix {
                            let value = try JSONElement(any: array.source.jsonObject(at: index))
                            try plan(pointer: pointer.appended(withIndex: index), comparison: .unchanged(value))
                        }
                    }
                case .change(let source, let target, let child):
                    let safe = allowCopySources && source == target && source < array.copySourcePrefix
                    try plan(pointer: pointer.appended(withIndex: target), comparison: child, allowCopySources: safe)
                case .remove(let indices):
                    for index in indices.reversed() { operations.append(.remove(path: pointer.appended(withIndex: index))) }
                case .insert(let index, let value, let append):
                    let path = append ? pointer.appended(withComponent: "-") : pointer.appended(withIndex: index)
                    operations.append(.add(path: path, value: value))
                }
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
            // Resolution replaces the add in place. Only maximal unchanged,
            // unshifted sources participate and remain valid throughout the patch.
            operations[index] = .copy(from: source.path, path: path)
        }
    }

}

extension JSONPatch {

    /// Initializes a JSONPatch instance with all json-patch operations required to transform the source
    /// json document into the target json document.
    ///
    /// Completely changed containers may use one replacement. Operation paths,
    /// ordering, and serialized bytes can change as generation strategies evolve.
    ///
    /// - Parameters:
    ///   - source: The source json document.
    ///   - target: The target json document.
    public convenience init(source: JSONElement, target: JSONElement) throws {
        self.init(operations: try JSONPatchGenerator.generatePatch(source: source, target: target))
    }

    /// Generates a patch with optional size/generation-time tradeoffs.
    /// Existing generation behavior applies when `generationOptions` is empty.
    public convenience init(source: JSONElement, target: JSONElement, generationOptions: [GenerationOption]) throws {
        self.init(operations: try JSONPatchGenerator.generatePatch(source: source, target: target,
                  preferSmallerPatch: generationOptions.contains(.preferSmallerPatch)))
    }

    /// Initialize a JSONPatch instance with all json-patch operations required to transform the source
    /// json document into the target json document.
    ///
    /// Completely changed containers may use one replacement. Operation paths,
    /// ordering, and serialized bytes can change as generation strategies evolve.
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

    /// Generates a patch from JSON data with optional size/generation-time tradeoffs.
    public convenience init(source: Data, target: Data, options: JSONSerialization.ReadingOptions = [],
                            generationOptions: [GenerationOption]) throws {
        let sourceJson = try JSONSerialization.jsonElement(with: source, options: options)
        let targetJson = try JSONSerialization.jsonElement(with: target, options: options)
        try self.init(source: sourceJson, target: targetJson, generationOptions: generationOptions)
    }
}
