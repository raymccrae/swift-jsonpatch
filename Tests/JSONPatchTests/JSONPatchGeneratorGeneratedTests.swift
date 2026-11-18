// Copyright © 2026 Raymond McCrae. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing
@testable import JSONPatch

struct JSONPatchGeneratorGeneratedTests {
    // Corpus v1: each (seed, caseIndex) is independent and printed by Swift Testing.
    // Reproduce a failure by running that pair through documents(seed:caseIndex:).
    @Test(arguments: [UInt64(0), 1, 1_729, 0xDEAD_BEEF_CAFE_BABE], 0..<32)
    func seededDocuments(seed: UInt64, caseIndex: Int) throws {
        let (source, target) = documents(seed: seed, caseIndex: caseIndex)
        let sourceJSON = try source.json()
        let targetJSON = try target.json()
        let context = "generated corpus v1, seed=\(seed), caseIndex=\(caseIndex)"
        // Verify the encoded fixtures against their independently built trees,
        // rather than letting generation and comparison share a parsing mistake.
        #expect(try GenerationJSON.parse(sourceJSON) == source, Comment(rawValue: context))
        #expect(try GenerationJSON.parse(targetJSON) == target, Comment(rawValue: context))
        try assertGeneratedPatch(source: sourceJSON, target: targetJSON, context: context) { patch in
            if source == target { #expect(patch.operations.isEmpty, Comment(rawValue: context)) }
            if caseIndex % 8 == 3 {
                let expected = try GenerationJSON.parse("[{\"op\":\"replace\",\"path\":\"/nested/a~1b/~0\",\"value\":\(caseIndex + 1_000)}]")
                #expect(try GenerationJSON(JSONSerialization.jsonObject(with: patch.data())) == expected,
                        Comment(rawValue: context))
                #expect(try patch.data().count < 128, Comment(rawValue: context))
            }
        }
    }

    private func documents(seed: UInt64, caseIndex: Int) -> (GenerationJSON, GenerationJSON) {
        var random = DocumentRandom(state: seed &+ UInt64(caseIndex) &* 0x9E37_79B9_7F4A_7C15)
        let value = random.document(depth: 3)
        switch caseIndex % 8 {
        case 0: return (value, value)
        case 1: return (value, random.document(depth: 3))
        case 2:
            var target = value
            for _ in 0..<3 { target = random.edit(target) }
            return (value, target)
        case 3:
            func wrapped(_ leaf: Int) -> GenerationJSON {
                .dictionary([("stable", value), ("nested", .dictionary([
                    ("a/b", .dictionary([("~", .number(Decimal(leaf)))])),
                    ("stable", value)
                ]))])
            }
            return (wrapped(caseIndex), wrapped(caseIndex + 1_000))
        case 4:
            let other = random.document(depth: 2)
            return (.dictionary([("donor", value), ("changing", other)]),
                    .dictionary([("donor", value), ("added", value), ("changing", random.edit(other))]))
        case 5:
            let source = GenerationJSON.array([value, value, random.document(depth: 2)])
            var target = source
            for _ in 0..<3 { target = random.edit(target) }
            return (source, target)
        case 6:
            let b = random.document(depth: 2)
            let c = random.document(depth: 2)
            return (.array([.array([value, b, c]), .array([])]),
                    .array([.array([value]), .array([c, b])]))
        default:
            let replacement = random.document(depth: 2)
            return (.dictionary([("a/b", .array([.dictionary([("", value)]), value]))]),
                    .dictionary([("a/b", .array([.dictionary([("", replacement)]), value]))]))
        }
    }
}

// SplitMix64 uses specified wrapping integer arithmetic, so seeds do not depend
// on Swift's randomized hashing or the host's random-number implementation.
private struct DocumentRandom {
    var state: UInt64
    private static let keys = ["", "a", "b", "0", "01", "a/b", "~", "\u{00e9}", "e\u{0301}"]
    private static let strings = ["", "plain", "/~", "quote\" newline\n tab\t", "\u{00e9}", "e\u{0301}", "🚀"]
    private static let numbers = ["0", "1", "-1", "1.25", "9007199254740992", "9007199254740993",
                                  "-9223372036854775808", "18446744073709551615"]

    mutating func integer(_ upperBound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int((value ^ (value >> 31)) % UInt64(upperBound))
    }

    // A tree has at most three container levels and four children per container.
    mutating func document(depth: Int) -> GenerationJSON {
        switch integer(depth == 0 ? 4 : 6) {
        case 0: return .null
        case 1: return .boolean(integer(2) == 0)
        case 2:
            return .number(Decimal(string: Self.numbers[integer(Self.numbers.count)],
                                   locale: Locale(identifier: "en_US_POSIX"))!)
        case 3: return .text(Self.strings[integer(Self.strings.count)])
        case 4:
            let count = integer(5)
            return .array((0..<count).map { _ in document(depth: depth - 1) })
        default:
            let count = integer(5)
            var entries: [GenerationJSON.Key: GenerationJSON] = [:]
            for _ in 0..<count {
                let key = GenerationJSON.Key(Self.keys[integer(Self.keys.count)])
                entries[key] = document(depth: depth - 1)
            }
            return .object(entries)
        }
    }

    // Derive related targets as well as unrelated pairs. Edits include insertion,
    // deletion, nested replacement, reversal, and duplication, with bounded growth.
    mutating func edit(_ value: GenerationJSON) -> GenerationJSON {
        switch value {
        case .object(var entries):
            let keys = entries.keys.sorted { $0.scalars.lexicographicallyPrecedes($1.scalars) }
            switch integer(3) {
            case 0:
                let key = GenerationJSON.Key(Self.keys[integer(Self.keys.count)])
                entries[key] = document(depth: 1)
            case 1 where !keys.isEmpty: entries.removeValue(forKey: keys[integer(keys.count)])
            default:
                if let key = keys.isEmpty ? nil : keys[integer(keys.count)] {
                    entries[key] = edit(entries[key]!)
                } else { entries[GenerationJSON.Key("")] = document(depth: 1) }
            }
            return .object(entries)
        case .array(var items):
            switch integer(5) {
            case 0: items.insert(document(depth: 1), at: integer(items.count + 1))
            case 1 where !items.isEmpty: items.remove(at: integer(items.count))
            case 2 where !items.isEmpty:
                let index = integer(items.count)
                items[index] = edit(items[index])
            case 3: items.reverse()
            default:
                if items.isEmpty { items.append(document(depth: 1)) }
                else { items.append(items[integer(items.count)]) }
            }
            return .array(items)
        default: return document(depth: 1)
        }
    }
}
