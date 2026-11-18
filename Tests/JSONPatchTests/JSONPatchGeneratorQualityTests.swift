// Copyright © 2026 Raymond McCrae. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing
@testable import JSONPatch

struct JSONPatchGeneratorQualityTests {
    @Test(arguments: [
        (#"{"keep":1}"#, #"{"keep":1,"new":2}"#, #"{"op":"add","path":"/new","value":2}"#),
        (#"{"keep":1,"old":2}"#, #"{"keep":1}"#, #"{"op":"remove","path":"/old"}"#),
        (#"{"value":1}"#, #"{"value":2}"#, #"{"op":"replace","path":"/value","value":2}"#),
        (#"{"nested":{"leaf":1,"keep":3}}"#, #"{"nested":{"leaf":2,"keep":3}}"#,
         #"{"op":"replace","path":"/nested/leaf","value":2}"#),
        (#"{"a/b":{"~":{"":1}}}"#, #"{"a/b":{"~":{"":2}}}"#,
         #"{"op":"replace","path":"/a~1b/~0/","value":2}"#),
        (#"{}"#, #"{"":null}"#, #"{"op":"add","path":"/","value":null}"#),
        (#"{"":null}"#, #"{}"#, #"{"op":"remove","path":"/"}"#),
        (#"{"v":null}"#, #"{"v":false}"#, #"{"op":"replace","path":"/v","value":false}"#),
        (#"{"v":true}"#, #"{"v":1}"#, #"{"op":"replace","path":"/v","value":1}"#),
        (#"{"v":9007199254740992}"#, #"{"v":9007199254740993}"#,
         #"{"op":"replace","path":"/v","value":9007199254740993}"#),
        (#"{"v":"\u00e9"}"#, #"{"v":"e\u0301"}"#,
         #"{"op":"replace","path":"/v","value":"e\u0301"}"#),
        ("[1,2]", "[1,3]", #"{"op":"replace","path":"/1","value":3}"#),
        ("[1,2,3]", "[1,2]", #"{"op":"remove","path":"/2"}"#)
    ])
    func singleEdit(source: String, target: String, operation: String) throws {
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            #expect(patch.operations.count == 1)
            #expect(try operations(patch) == [GenerationJSON.parse(operation)])
        }
    }

    @Test func appendUsesOneInsertion() throws {
        try assertGeneratedPatch(source: "[1,2]", target: "[1,2,3]") { (patch: JSONPatch) throws -> Void in
            #expect(patch.operations.count == 1)
            let operation = try #require(patch.operations.first)
            guard case .add(let path, let value) = operation else { Issue.record("Expected one insertion"); return }
            #expect(["/-", "/2"].contains(path.string))
            #expect(try GenerationJSON(value.rawValue) == .number(3))
        }
    }

    @Test(arguments: [("null", "{}"), ("{}", "[]"), ("[]", #""done""#),
                      ("false", "0"), ("1", "true"), (#""""#, "null"), ("1", "2")])
    func rootReplacement(source: String, target: String) throws {
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            let expected = try GenerationJSON.parse("{\"op\":\"replace\",\"path\":\"\",\"value\":" + target + "}")
            #expect(try operations(patch) == [expected])
        }
    }

    @Test(arguments: ["null", "true", "1", #""text""#, "[]", "{}",
                      #"{"a":[null,true,1,{},[]],"\u00e9":1,"e\u0301":2}"#])
    func separatelyParsedEqualDocuments(json: String) throws {
        try assertGeneratedPatch(source: json, target: json) { (patch: JSONPatch) throws -> Void in
            #expect(patch.operations.isEmpty)
            #expect(try patch.data().count == 2) // []
        }
    }

    @Test func disjointEditsHaveNoRedundantOperations() throws {
        let source = #"{"remove":0,"change":1,"nested":{"remove":2,"change":3,"keep":4},"keep":5}"#
        let target = #"{"added":6,"change":7,"nested":{"added":8,"change":9,"keep":4},"keep":5}"#
        let expected = try GenerationJSON.parse(#"""
            [
                {"op":"remove","path":"/remove"},
                {"op":"add","path":"/added","value":6},
                {"op":"replace","path":"/change","value":7},
                {"op":"remove","path":"/nested/remove"},
                {"op":"add","path":"/nested/added","value":8},
                {"op":"replace","path":"/nested/change","value":9}
            ]
            """#)
        guard case .array(let expectedOperations) = expected else { Issue.record("Expected operations"); return }
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            let actual = try operations(patch)
            #expect(actual.count == expectedOperations.count)
            // These object edits are independent; their ordering is not a contract.
            for operation in expectedOperations { #expect(actual.contains(operation)) }
        }
    }

    @Test func smallEditDoesNotReplaceLargeUnchangedSubtrees() throws {
        let stable = try largeValue(kind: 2).json()
        let source = "{\"stable\":" + stable + ",\"nested\":{\"stable\":" + stable + ",\"leaf\":1}}"
        let target = "{\"stable\":" + stable + ",\"nested\":{\"stable\":" + stable + ",\"leaf\":2}}"
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            #expect(try operations(patch) == [GenerationJSON.parse(#"{"op":"replace","path":"/nested/leaf","value":2}"#)])
            #expect(try patch.data().count < 128)
        }
    }

    @Test(arguments: 0..<3, [false, true])
    func compactCopyFromBeforeOrAfterAddition(kind: Int, donorFirst: Bool) throws {
        let payload = try largeValue(kind: kind).json()
        // Array order forces discovery on either side of the addition regardless
        // of object key enumeration. The whole donor remains at a stable path.
        let source = donorFirst ? "[\(payload),{}]" : "[{},\(payload)]"
        let target = donorFirst ? "[\(payload),{\"added\":\(payload)}]" : "[{\"added\":\(payload)},\(payload)]"
        let from = donorFirst ? "/0" : "/1"
        let path = donorFirst ? "/1/added" : "/0/added"
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            #expect(try operations(patch) == [GenerationJSON.parse("{\"op\":\"copy\",\"from\":\"\(from)\",\"path\":\"\(path)\"}")])
            // A generous envelope protects the useful copy, not encoder field order.
            #expect(try patch.data().count < 256)
        }
    }

    @Test func equivalentCopyDonorsMayBeChosenInAnyOrder() throws {
        let payload = try largeValue(kind: 2).json()
        let source = "{\"left/~\":\(payload),\"right\":\(payload)}"
        let target = "{\"left/~\":\(payload),\"right\":\(payload),\"added\":\(payload)}"
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            #expect(patch.operations.count == 1)
            let operation = try #require(patch.operations.first)
            guard case .copy(let from, let path) = operation else { Issue.record("Expected a compact copy"); return }
            #expect(["/left~1~0", "/right"].contains(from.string))
            #expect(path.string == "/added")
            #expect(try patch.data().count < 256)
        }
    }

    @Test(arguments: [false, true])
    func copyFromUnchangedChildOfChangingAncestor(donorFirst: Bool) throws {
        let payload = try largeValue(kind: 2).json()
        let before = "{\"stable\":\(payload),\"changing\":0}"
        let after = "{\"stable\":\(payload),\"changing\":1}"
        let source = donorFirst ? "[\(before),{}]" : "[{},\(before)]"
        let target = donorFirst ? "[\(after),{\"added\":\(payload)}]" : "[{\"added\":\(payload)},\(after)]"
        let donor = donorFirst ? 0 : 1
        let destination = donorFirst ? 1 : 0
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            let actual = try operations(patch)
            let copy = try GenerationJSON.parse("{\"op\":\"copy\",\"from\":\"/\(donor)/stable\",\"path\":\"/\(destination)/added\"}")
            let replacement = try GenerationJSON.parse("{\"op\":\"replace\",\"path\":\"/\(donor)/changing\",\"value\":1}")
            #expect(actual.count == 2)
            #expect(actual.contains(copy))
            #expect(actual.contains(replacement))
            #expect(try patch.data().count < 384)
        }
    }

    @Test(arguments: ["", "a/b~"])
    func copyPathsEscapeSourceAndDestination(donor: String) throws {
        let payload = largeValue(kind: 0)
        let source = try GenerationJSON.dictionary([(donor, payload)]).json()
        let target = try GenerationJSON.dictionary([(donor, payload), ("~target/", payload)]).json()
        let from = donor.isEmpty ? "/" : "/a~1b~0"
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            let expected = try GenerationJSON.parse("{\"op\":\"copy\",\"from\":\"\(from)\",\"path\":\"/~0target~1\"}")
            #expect(try operations(patch) == [expected])
            #expect(try patch.data().count < 256)
        }
    }

    @Test(arguments: [
        (#"{"obsolete":[1,2,3],"stable":[1,2,3]}"#, #"{"added":[1,2,3],"stable":[1,2,3]}"#),
        (#"{"changed":[1,2,3],"stable":[1,2,3]}"#, #"{"changed":false,"added":[1,2,3],"stable":[1,2,3]}"#),
        (#"[{},[1,2,3]]"#, #"[{"added":[1,2,3]}]"#),
        (#"[[[1,2,3],[1,2,3]],[]]"#, #"[[[1,2,3]],[[1,2,3]]]"#),
        (#"[[1,2,3],[],[]]"#, #"[[1],[2],[3]]"#),
        (#"[[[1],[2],[3]],[]]"#, #"[[[1]],[[2],[3]]]"#),
        (#"[[{"a":1},{"a":1}],[]]"#, #"[[{"a":2}],[{"a":1}]]"#)
    ])
    func copySourcesRemainValidThroughSequentialEdits(source: String, target: String) throws {
        try assertGeneratedPatch(source: source, target: target)
    }

    @Test func generationDoesNotReuseStaleMutableStateAcrossCalls() throws {
        let source = NSMutableDictionary(dictionary: ["value": 1])
        let target = NSMutableDictionary(dictionary: ["value": 2])
        _ = try JSONPatch(source: .mutableObject(value: source), target: .mutableObject(value: target))
        source["value"] = 3
        target["value"] = 4
        let patch = try JSONPatch(source: .mutableObject(value: source), target: .mutableObject(value: target))
        #expect(try operations(patch) == [GenerationJSON.parse(#"{"op":"replace","path":"/value","value":4}"#)])
        #expect(try GenerationJSON(patch.apply(to: source, options: [.applyOnCopy])) == GenerationJSON.parse(#"{"value":4}"#))
        #expect(try GenerationJSON(source) == GenerationJSON.parse(#"{"value":3}"#))
        #expect(try GenerationJSON(target) == GenerationJSON.parse(#"{"value":4}"#))
    }

    @Test(arguments: [1, 2])
    func sharedMutableSubtreesRemainSafeAcrossCalls(kind: Int) throws {
        let shared = try GenerationJSON.read(largeValue(kind: kind).json(), mutable: true)
        let source = NSMutableDictionary(dictionary: ["stable": shared, "edit": 0])
        let target = NSMutableDictionary(dictionary: ["stable": shared, "added": shared, "edit": 1])
        for revision in [0, 1] {
            if let object = shared as? NSMutableDictionary { object["revision"] = revision }
            else {
                let array = try #require(shared as? NSMutableArray)
                array[0] = revision
            }
            source["edit"] = revision
            target["edit"] = revision + 1
            let expectedSource = try GenerationJSON(source)
            let expectedTarget = try GenerationJSON(target)
            let sourceData = try JSONSerialization.data(withJSONObject: source)
            let patch = try JSONPatch(source: .mutableObject(value: source), target: .mutableObject(value: target))
            let actual = try operations(patch)
            #expect(actual.count == 2)
            #expect(try actual.contains(GenerationJSON.parse(#"{"op":"copy","from":"/stable","path":"/added"}"#)))
            #expect(try actual.contains(GenerationJSON.parse("{\"op\":\"replace\",\"path\":\"/edit\",\"value\":\(revision + 1)}")))
            for reusable in [patch, try JSONPatch(data: patch.data())] {
                let fresh = try JSONSerialization.jsonObject(with: sourceData, options: [.mutableContainers])
                #expect(try GenerationJSON(reusable.apply(to: fresh)) == expectedTarget)
                #expect(try GenerationJSON(reusable.apply(to: source, options: [.applyOnCopy])) == expectedTarget)
            }
            #expect(try GenerationJSON(source) == expectedSource)
            #expect(try GenerationJSON(target) == expectedTarget)
        }
    }

    @Test(arguments: [("null", "[true,9007199254740993]"),
                      (#"{"a/b":1}"#, #"{"a/b":2,"":null}"#)])
    func dataInitializerPreservesGenerationQuality(source: String, target: String) throws {
        let direct = try JSONPatch(source: Data(source.utf8), target: Data(target.utf8), options: [.fragmentsAllowed])
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            // Compare operation membership, not independent object edit order.
            let actual = try operations(direct)
            let expected = try operations(patch)
            #expect(actual.count == expected.count)
            for operation in expected { #expect(actual.contains(operation)) }
        }
        let decoded = try JSONPatch(data: direct.data())
        #expect(try GenerationJSON(decoded.apply(to: GenerationJSON.read(source))) == GenerationJSON.parse(target))
    }

    private func operations(_ patch: JSONPatch) throws -> [GenerationJSON] {
        let value = try GenerationJSON(JSONSerialization.jsonObject(with: patch.data()))
        return try #require({ if case .array(let operations) = value { return operations }; return nil }())
    }

    private func largeValue(kind: Int) -> GenerationJSON {
        switch kind {
        case 0: return .text(String(repeating: "payload/~\n", count: 1_024))
        case 1: return .array((0..<512).map { .number(Decimal($0)) })
        default: return .dictionary([("text", largeValue(kind: 0)), ("items", largeValue(kind: 1))])
        }
    }
}

struct JSONPatchCopyEncodingTests {
    @Test(arguments: ["0", "true", "false", "null", "[]", "{}", #""aa""#])
    func tinyLiteralsDoNotUseLongCopyPaths(value: String) throws {
        let key = String(repeating: "long/~", count: 20)
        let encodedKey = try GenerationJSON.text(key).json()
        let source = "{\(encodedKey):\(value)}"
        let target = "{\(encodedKey):\(value),\"destination/~\":\(value)}"
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            #expect(patch.operations.count == 1)
            guard case .add(let path, let literal) = try #require(patch.operations.first) else {
                Issue.record("A tiny literal should beat the long copy source"); return
            }
            #expect(path.string == "/destination~1~0")
            #expect(try GenerationJSON(literal.rawValue) == GenerationJSON.parse(value))
        }
    }

    @Test(arguments: [(#""aaa""#, false), (#""aaaa""#, true), (#""a/a""#, true)])
    func copyMustStrictlyReduceDefaultEncodedSize(value: String, expectCopy: Bool) throws {
        try assertGeneratedPatch(source: "{\"a\":\(value)}", target: "{\"a\":\(value),\"added\":\(value)}") { (patch: JSONPatch) throws -> Void in
            let operation = try #require(patch.operations.first)
            let literal = try JSONElement(any: GenerationJSON.read(value))
            let add = JSONPatch(operations: [.add(path: try JSONPointer(string: "/added"), value: literal)])
            let copy = JSONPatch(operations: [.copy(from: try JSONPointer(string: "/a"), path: try JSONPointer(string: "/added"))])
            #expect((try copy.data().count < add.data().count) == expectCopy)
            if expectCopy {
                guard case .copy = operation else { Issue.record("Expected a smaller copy"); return }
            } else {
                guard case .add = operation else { Issue.record("Ties should retain the literal"); return }
            }
        }
    }

    @Test(arguments: [1, 20])
    func shortestStableDonorWinsForLinearAndIndexedLookup(additions: Int) throws {
        let payload = GenerationJSON.text(String(repeating: "payload", count: 100))
        var entries: [(String, GenerationJSON)] = [("b", payload), ("a", payload), ("~~~~", payload)]
        entries += (0..<32).map { ("filler\($0)", .text("different-\($0)")) }
        let source = try GenerationJSON.dictionary(entries).json()
        let target = try GenerationJSON.dictionary(entries + (0..<additions).map { ("added\($0)", payload) }).json()
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            #expect(patch.operations.count == additions)
            for operation in patch.operations {
                guard case .copy(let from, _) = operation else { Issue.record("Expected useful copies"); continue }
                #expect(from.string == "/a")
            }
        }
    }

    @Test func escapedByteCostDeterminesShortestSource() throws {
        let payload = GenerationJSON.text(String(repeating: "x", count: 100))
        let source = try GenerationJSON.dictionary([("~~", payload), ("aaa", payload)]).json()
        let target = try GenerationJSON.dictionary([("~~", payload), ("aaa", payload), ("added", payload)]).json()
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            guard case .copy(let from, _) = try #require(patch.operations.first) else { Issue.record("Expected copy"); return }
            #expect(from.string == "/aaa")
        }
    }
}

struct JSONPatchCopyIndexTests {
    private func element(_ json: String, mutable: Bool = false) throws -> JSONElement {
        try JSONElement(any: GenerationJSON.read(json, mutable: mutable))
    }

    @Test func boundedLiteralSizesMatchFoundation() throws {
        let controls = String(String.UnicodeScalarView((0..<32).map { Unicode.Scalar($0)! }))
        let strings = ["", "/~\\\"", controls, "é/e\u{0301}/🚀", "\u{2028}\u{2029}"]
        var values = try strings.map { try element(GenerationJSON.text($0).json()) }
        values += try ["null", "true", "false", "0", "-1", "1.0", "1.25", "1e-20", "1e100",
                       "9007199254740993", "18446744073709551615", "-9223372036854775808",
                       "[]", "{}", #"{"":null,"a/b~":[true,1,"x"]}"#,
                       #"{"\u00e9":1,"e\u0301":2}"#].map { try element($0) }
        values.append(.number(value: NSDecimalNumber(string: "1234567890.123456789")))
        let typed: [NSNumber] = [NSNumber(value: Int8.min), NSNumber(value: UInt8.max),
                                 NSNumber(value: Int16.min), NSNumber(value: UInt16.max),
                                 NSNumber(value: Int32.min), NSNumber(value: UInt32.max),
                                 NSNumber(value: Int64.min), NSNumber(value: UInt64.max),
                                 NSNumber(value: Float(0.1)), NSNumber(value: -0.0)]
        values += typed.map { .number(value: $0) }
        for value in values {
            let count = try JSONSerialization.data(withJSONObject: value.rawValue, options: [.fragmentsAllowed]).count
            for limit in 0...(count + 2) {
                #expect(JSONPatchGenerator.CopyCost.literalSize(value, limit: limit) == min(count, limit + 1))
            }
        }
    }

    @Test func operationMetadataAndDestinationCancelInSizeComparison() throws {
        let values = [try element(#"{"v":"/~é\u2028","n":1.25}"#),
                      JSONElement.number(value: NSNumber(value: 1.23456789)),
                      JSONElement.number(value: NSNumber(value: Double.greatestFiniteMagnitude)),
                      JSONElement.number(value: NSDecimalNumber(string: "1234567890.123456789"))]
        for value in values {
            let literalBytes = try JSONSerialization.data(withJSONObject: value.rawValue, options: [.fragmentsAllowed]).count
            for sourcePath in ["", "/", "/a", "/~0~1", "/é\n🚀"] {
                let from = try JSONPointer(string: sourcePath)
                let source = JSONPatchGenerator.CopySource(path: from, value: value)
                let actualPathBytes = try JSONSerialization.data(withJSONObject: from.string, options: [.fragmentsAllowed]).count
                #expect(source.encodedBytes == actualPathBytes)
                for destination in ["", "/x", "/~1~0/é\t"] {
                    let path = try JSONPointer(string: destination)
                    let add = JSONPatch(operations: [.add(path: path, value: value)])
                    let copy = JSONPatch(operations: [.copy(from: from, path: path)])
                    #expect(try copy.data().count - add.data().count == source.encodedBytes - literalBytes)
                }
            }
        }
    }

    @Test(arguments: [
        ("1", "1.0"), ("0", "-0.0"),
        (#"{"a":1,"b":[true,null]}"#, #"{"b":[true,null],"a":1.0}"#),
        (#"{"\u00e9":1,"e\u0301":2}"#, #"{"e\u0301":2,"\u00e9":1.0}"#)
    ])
    func equalValuesHaveCompatibleFingerprints(a: String, b: String) throws {
        let first = try element(a)
        let second = try element(b, mutable: true)
        #expect(try GenerationJSON(first.rawValue) == GenerationJSON(second.rawValue))
        #expect(JSONPatchGenerator.copyFingerprint(first) == JSONPatchGenerator.copyFingerprint(second))
    }

    @Test(arguments: [
        ("true", "1"), ("[1,2]", "[2,1]"),
        (#"{"n":9007199254740992}"#, #"{"n":9007199254740993}"#),
        (#"{"":null}"#, "{}"),
        (#"{"\u00e9":1}"#, #"{"e\u0301":1}"#),
        (#"{"\u00e9":1,"e\u0301":2}"#, #"{"\u00e9":2,"e\u0301":1}"#)
    ])
    func forcedHashCollisionsStillRequireExactEquality(wrong: String, wanted: String) throws {
        let bad = try element(wrong)
        let good = try element(wanted)
        let sources = [JSONPatchGenerator.CopySource(path: try JSONPointer(string: "/a"), value: bad),
                       JSONPatchGenerator.CopySource(path: try JSONPointer(string: "/b"), value: good)]
        let index = JSONPatchGenerator.CopyIndex(orderedSources: sources, fingerprint: { _ in 0 })
        let match = try #require(index.source(for: good, fingerprint: 0))
        #expect(match.path.string == "/b")
        #expect(try GenerationJSON(match.value.rawValue) == GenerationJSON(good.rawValue))
        let single = JSONPatchGenerator.CopyIndex(orderedSources: [sources[0]], fingerprint: { _ in 0 })
        #expect(single.source(for: good, fingerprint: 0) == nil)
    }

    @Test func lazyIndexAmortizesMissesAndKeepsCheapHitsLinear() throws {
        let sources = try (0..<32).map {
            JSONPatchGenerator.CopySource(path: try JSONPointer(string: "/s\($0)"), value: JSONElement("source-\($0)"))
        }
        var misses = JSONPatchGenerator.CopyLookup(sources: sources)
        for remaining in (1...20).reversed() {
            #expect(misses.source(for: JSONElement("missing"), remainingQueries: remaining) == nil)
        }
        #expect(misses.builtIndex)
        #expect(misses.linearComparisons < sources.count * 20 / 2)
        let found = misses.source(for: JSONElement("source-9"), remainingQueries: 1)
        let match = try #require(found)
        #expect(match.path.string == "/s9")
        var hits = JSONPatchGenerator.CopyLookup(sources: sources)
        for remaining in (1...20).reversed() {
            #expect(hits.source(for: JSONElement("source-0"), remainingQueries: remaining)?.path.string == "/s0")
        }
        #expect(!hits.builtIndex)
        #expect(hits.linearComparisons <= sources.count)
    }

    @Test func unselectiveFingerprintsFallBackWithoutChangingResults() throws {
        let prefix = String(repeating: "x", count: 40)
        let sources = try (0..<32).map {
            JSONPatchGenerator.CopySource(path: try JSONPointer(string: "/s\($0)"), value: JSONElement(prefix + String(format: "%02d", $0)))
        }
        var lookup = JSONPatchGenerator.CopyLookup(sources: sources)
        for remaining in (1...20).reversed() {
            #expect(lookup.source(for: JSONElement(prefix + "zz"), remainingQueries: remaining) == nil)
        }
        #expect(lookup.builtIndex)
        #expect(lookup.linearComparisons <= sources.count * 20)
        #expect(lookup.source(for: JSONElement(prefix + "17"), remainingQueries: 1)?.path.string == "/s17")
    }

    @Test func indexedCopiesSurviveTailRemovalAndPatchReuse() throws {
        let values = (0..<32).map { index in
            GenerationJSON.dictionary([("id", .text("id-\(index)")), ("body", .text(String(repeating: "x", count: 100)))])
        }
        let source = try GenerationJSON.array([.array(values), .array([])]).json()
        let target = try GenerationJSON.array([.array(Array(values.prefix(31))), .array(Array(values[10...31]))]).json()
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            var copies = 0
            var additions = 0
            for operation in patch.operations {
                if case .copy(let from, _) = operation { copies += 1; #expect(from.string != "/0/31") }
                if case .add = operation { additions += 1 }
            }
            #expect(copies == 21)
            #expect(additions == 1) // Removed source 31 must be encoded literally.
        }
    }
}

struct JSONPatchAdaptiveGenerationTests {
    @Test func smallerPatchOptionCompactsPartialChanges() throws {
        let source = "{" + (0..<100).map { "\"k\($0)\":\($0)" }.joined(separator: ",") + "}"
        let target = "{" + (0..<100).map { "\"k\($0)\":\($0 < 90 ? $0 + 100 : $0)" }.joined(separator: ",") + "}"
        let detailed = try JSONPatch(source: Data(source.utf8), target: Data(target.utf8))
        #expect(detailed.operations.count == 90)
        try assertGeneratedPatch(source: source, target: target, generationOptions: [.preferSmallerPatch]) { (patch: JSONPatch) throws -> Void in
            #expect(patch.operations.count == 1)
            #expect(try patch.data().count < detailed.data().count)
        }
    }

    @Test func smallerPatchOptionKeepsSparseEditsAndCompactCopies() throws {
        let body = try GenerationJSON.text(String(repeating: "payload", count: 1_000)).json()
        try assertGeneratedPatch(source: "{\"a\":0,\"b\":0,\"stable\":\(body)}",
                                 target: "{\"a\":1,\"b\":1,\"stable\":\(body)}",
                                 generationOptions: [.preferSmallerPatch]) { patch in
            #expect(patch.operations.count == 2)
        }
        let copies = (0..<30).map { "\"added\($0)\":\(body)" }.joined(separator: ",")
        try assertGeneratedPatch(source: "{\"stable\":\(body)}",
                                 target: "{\"stable\":\(body),\(copies)}",
                                 generationOptions: [.preferSmallerPatch]) { patch in
            #expect(patch.operations.count == 30)
            #expect(patch.operations.allSatisfy { if case .copy = $0 { return true }; return false })
        }
    }

    @Test func sizeTiesRetainDetailedOperations() throws {
        var foundTie = false
        for count in 0...128 {
            let body = String(repeating: "x", count: count)
            let source = Data("{\"a\":0,\"b\":0,\"stable\":\"\(body)\"}".utf8)
            let target = Data("{\"a\":1,\"b\":1,\"stable\":\"\(body)\"}".utf8)
            let detailed = try JSONPatch(source: source, target: target)
            let element = try JSONSerialization.jsonElement(with: target, options: [])
            let replacement = JSONPatch(operations: [.replace(path: .wholeDocument, value: element)])
            if try detailed.data().count == replacement.data().count {
                foundTie = true
                let selected = try JSONPatch(source: source, target: target, generationOptions: [.preferSmallerPatch])
                #expect(selected.operations.count == detailed.operations.count)
                break
            }
        }
        #expect(foundTie)
    }

    @Test func operationCostMatchesFoundationAndHonorsLimits() throws {
        let path = try JSONPointer(string: "/a~1b/~0/\u{e9}")
        let value = try JSONElement(any: GenerationJSON.read(#"[true,9007199254740993,1.2345,"\n/🚀"]"#))
        let operations: [JSONPatch.Operation] = [
            .add(path: path, value: value), .replace(path: path, value: value),
            .remove(path: path), .copy(from: .wholeDocument, path: path),
            .move(from: path, path: .wholeDocument), .test(path: path, value: value)
        ]
        for operation in operations {
            let expected = try JSONPatch(operations: [operation]).data().count - 2
            #expect(JSONPatchGenerator.ReplacementCost.operationSize(operation, limit: expected) == expected)
            #expect(JSONPatchGenerator.ReplacementCost.operationSize(operation, limit: expected - 1) == nil)
        }
        var deep: JSONElement = .null
        for _ in 0..<17 { deep = .array(value: NSArray(object: deep.rawValue)) }
        #expect(JSONPatchGenerator.CopyCost.literalSize(deep, limit: 65_536, remainingDepth: 16) == nil)
        let deepPath = try JSONPointer(string: String(repeating: "/a", count: 33))
        #expect(JSONPatchGenerator.ReplacementCost.operationSize(.remove(path: deepPath), limit: 65_536) == nil)
        let tooMany = Array(repeating: JSONPatch.Operation.remove(path: path), count: 2_049)
        #expect(!JSONPatchGenerator.ReplacementCost.prefersReplacement(tooMany, target: .null))
        let large = JSONElement.string(value: String(repeating: "x", count: 100) as NSString)
        let tooManyBytes = Array(repeating: JSONPatch.Operation.replace(path: path, value: large), count: 1_000)
        #expect(!JSONPatchGenerator.ReplacementCost.prefersReplacement(tooManyBytes, target: .null))
    }

    @Test func existingInitializerReferencesAndEmptyOptionsRemainCompatible() throws {
        let old: (JSONElement, JSONElement) throws -> JSONPatch = JSONPatch.init(source:target:)
        let oldData: (Data, Data, JSONSerialization.ReadingOptions) throws -> JSONPatch = JSONPatch.init(source:target:options:)
        let source = try JSONElement(any: GenerationJSON.read("[0,1,2]"))
        let target = try JSONElement(any: GenerationJSON.read("[3,4,2]"))
        let original = try old(source, target)
        let empty = try JSONPatch(source: source, target: target, generationOptions: [])
        #expect(try original.data().count == empty.data().count)
        #expect(try oldData(Data("[0,1,2]".utf8), Data("[3,4,2]".utf8), []).operations.count == 2)
    }

    @Test(arguments: [2, 10, 32, 1_000])
    func completeArrayChangesUseOneReplacement(count: Int) throws {
        let values = (0..<count).map(String.init)
        try assertGeneratedPatch(source: "[" + values.joined(separator: ",") + "]",
                                 target: "[" + (count..<(2 * count)).map(String.init).joined(separator: ",") + "]") { patch in
            #expect(patch.operations.count == 1)
            if case .replace(let path, _) = patch.operations.first { #expect(path == .wholeDocument) }
            else { Issue.record("Expected a container replacement") }
        }
    }

    @Test func completeObjectChangesUseOneNestedReplacement() throws {
        let source = "{" + (0..<32).map { "\"k\($0)\":\($0)" }.joined(separator: ",") + "}"
        let target = "{" + (0..<32).map { "\"k\($0)\":\($0 + 100)" }.joined(separator: ",") + "}"
        try assertGeneratedPatch(source: "{\"nested\":\(source),\"stable\":true}",
                                 target: "{\"nested\":\(target),\"stable\":true}") { patch in
            #expect(patch.operations.count == 1)
            if case .replace(let path, _) = patch.operations.first { #expect(path.string == "/nested") }
            else { Issue.record("Expected a nested container replacement") }
        }
    }

    @Test func partialChangesAndSingletonsKeepFocusedEdits() throws {
        for count in [31, 32] {
            let source = "{" + (0..<count).map { "\"k\($0)\":\($0)" }.joined(separator: ",") + "}"
            let target = "{" + (0..<count).map { "\"k\($0)\":\($0 == 0 ? 0 : $0 + 100)" }.joined(separator: ",") + "}"
            try assertGeneratedPatch(source: source, target: target) { patch in
                #expect(patch.operations.count == count - 1)
            }
        }
        try assertGeneratedPatch(source: "{\"nested\":[1]}", target: "{\"nested\":[2]}") { patch in
            #expect(patch.operations.count == 1)
            if case .replace(let path, _) = patch.operations.first { #expect(path.string == "/nested/0") }
            else { Issue.record("Expected a leaf replacement") }
        }
    }

    @Test func replacementByteSavingsIncludeEscapedKeysAndNestedValues() throws {
        let keys = (0..<32).map { "\($0)/~\"\n\u{e9}e\u{301}" }
        let source = GenerationJSON.dictionary(keys.enumerated().map { ($0.element, .number(Decimal($0.offset))) })
        let payload = GenerationJSON.dictionary([("items", .array([.boolean(true), .text(String(repeating: "x", count: 1024))]))])
        let target = GenerationJSON.dictionary(keys.map { ($0, payload) })
        let expected = try #require(GenerationJSON.read(target.json()) as? NSDictionary)
        let detailed = try JSONPatch(operations: keys.map { key in
            let path = try JSONPointer(string: "/nested/" + JSONPointer.escape(key))
            let raw = try #require(expected.jsonObject(forKey: key as NSString))
            return .replace(path: path, value: try JSONElement(any: raw))
        })
        try assertGeneratedPatch(source: "{\"nested\":\(source.json())}",
                                 target: "{\"nested\":\(target.json())}") { (patch: JSONPatch) throws -> Void in
            #expect(patch.operations.count == 1)
            #expect(try patch.data().count < detailed.data().count)
        }
    }

    @Test func containerReplacementDoesNotRemoveExternalCopySources() throws {
        let body = try GenerationJSON.text(String(repeating: "payload", count: 1_000)).json()
        let source = "[" + (0..<32).map(String.init).joined(separator: ",") + "]"
        let target = "[" + (100..<132).map(String.init).joined(separator: ",") + "]"
        try assertGeneratedPatch(source: "[\(source),\(body),[]]",
                                 target: "[\(target),\(body),[\(body)]]") { patch in
            #expect(patch.operations.count == 2)
            #expect(patch.operations.contains { if case .copy(let from, _) = $0 { return from.string == "/1" }; return false })
        }
    }

    @Test func dataInitializerUsesTheSameAdaptivePolicy() throws {
        let source = "[0,1]"
        let target = "[2,3]"
        let patch = try JSONPatch(source: Data(source.utf8), target: Data(target.utf8), options: [.mutableContainers])
        #expect(patch.operations.count == 1)
        let result = try JSONPatch(data: patch.data()).apply(to: GenerationJSON.read(source))
        #expect(try GenerationJSON(result) == GenerationJSON.parse(target))
    }
}

struct JSONPatchArrayGenerationTests {
    @Test(arguments: [
        ("[1,2,3]", "[0,1,2,3]", #"[{"op":"add","path":"/0","value":0}]"#),
        ("[0,1,3]", "[0,1,2,3]", #"[{"op":"add","path":"/2","value":2}]"#),
        ("[0,1,2,3]", "[0,2,3]", #"[{"op":"remove","path":"/1"}]"#),
        ("[0,3]", "[0,1,2,3]", #"[{"op":"add","path":"/1","value":1},{"op":"add","path":"/2","value":2}]"#),
        ("[0,1,2,3]", "[0,3]", #"[{"op":"remove","path":"/2"},{"op":"remove","path":"/1"}]"#),
        (#"[{"leaf":1,"stable":[1,2,3]}]"#, #"[{"leaf":2,"stable":[1,2,3]}]"#,
         #"[{"op":"replace","path":"/0/leaf","value":2}]"#)
    ])
    func focusedArrayEdits(source: String, target: String, operations: String) throws {
        try assertGeneratedPatch(source: source, target: target) { (patch: JSONPatch) throws -> Void in
            let actual = try GenerationJSON(JSONSerialization.jsonObject(with: patch.data()))
            #expect(try actual == GenerationJSON.parse(operations))
        }
    }

    @Test(arguments: ["[0,1,0,1,0]", "[0,1,2,3,4]", "[0,1,2,3,4,5,6,7,8,9]"])
    func rotationRetainsSequenceWithTwoEdits(source: String) throws {
        let original = try GenerationJSON.parse(source)
        guard case .array(let values) = original else { Issue.record("Expected array"); return }
        let target = try GenerationJSON.array(Array(values.dropFirst()) + [values[0]]).json()
        try assertGeneratedPatch(source: source, target: target) { patch in
            #expect(patch.operations.count == 2)
            for operation in patch.operations {
                if case .move = operation { Issue.record("Automatic move generation remains deferred") }
            }
        }
    }

    @Test func boundedMatchingHandlesLongRotationAndFallsBackOnReversal() throws {
        let values = (0..<10_000).map { NSNumber(value: $0) }
        let source = NSArray(array: values)
        let rotated = NSArray(array: Array(values.dropFirst()) + [values[0]])
        let rotation = try JSONPatchGenerator.ArrayMatching.align(source, rotated)
        #expect(!rotation.usedFallback)
        #expect(rotation.matches.count == values.count - 1)
        let reversal = try JSONPatchGenerator.ArrayMatching.align(source, NSArray(array: Array(values.reversed())))
        #expect(reversal.usedFallback)
        #expect(reversal.work <= JSONPatchGenerator.ArrayMatching.maximumWork)
        #expect(reversal.traceEntries <= 171)
    }

    @Test func smallReversalsDoNotInflateTheOperationCount() throws {
        for length in [4, 5, 10] {
            let values = (0..<length).map(String.init)
            try assertGeneratedPatch(source: "[" + values.joined(separator: ",") + "]",
                                     target: "[" + values.reversed().joined(separator: ",") + "]") { patch in
                #expect(patch.operations.count <= length)
            }
        }
    }

    @Test func largeNestedValuesStopExtraMatchingAtTheBudget() throws {
        let body = String(repeating: "x", count: 100_000)
        let literal = try GenerationJSON.text(body).json()
        let source = "[\(literal)]"
        let target = "[0,\(literal)]"
        let a = try #require(GenerationJSON.read(source) as? NSArray)
        let b = try #require(GenerationJSON.read(target) as? NSArray)
        let limited = try JSONPatchGenerator.ArrayMatching.align(a, b, workLimit: 32)
        #expect(limited.usedFallback)
        #expect(limited.work <= 32)
        #expect(limited.traceEntries * MemoryLayout<Int>.stride <= 64 * 1024)
        try assertGeneratedPatch(source: source, target: target)
    }

    @Test func arrayShiftsCannotInvalidateLaterCopySources() throws {
        let payload = try GenerationJSON.text(String(repeating: "payload", count: 100)).json()
        try assertGeneratedPatch(source: "[[\(payload),1,2],[]]", target: "[[0,\(payload),1,2],[\(payload)]]") { patch in
            for operation in patch.operations {
                if case .copy(let from, _) = operation { #expect(from.string != "/0/0") }
            }
        }
    }

    @Test func unchangedPrefixAndExternalDonorsStillProduceCopies() throws {
        let payload = try GenerationJSON.text(String(repeating: "payload", count: 100)).json()
        // Interior insertion shifts the suffix, but source /0/0 never moves.
        try assertGeneratedPatch(source: "[[\(payload),1,2],[]]", target: "[[\(payload),0,1,2],[\(payload)]]") { patch in
            #expect(patch.operations.contains { if case .copy(let from, _) = $0 { return from.string == "/0/0" }; return false })
        }
        try assertGeneratedPatch(source: "{\"stable\":\(payload),\"array\":[1,2,3]}",
                                 target: "{\"stable\":\(payload),\"array\":[\(payload),1,2,3]}") { patch in
            #expect(patch.operations.count == 1)
            #expect(patch.operations.contains { if case .copy(let from, let path) = $0 { return from.string == "/stable" && path.string == "/array/0" }; return false })
        }
    }

    @Test func booleanNumericAndUnicodeIdentityRemainExactDuringMatching() throws {
        try assertGeneratedPatch(source: #"[true,9007199254740992,{"\u00e9":1,"e\u0301":2}]"#,
                                 target: #"[0,true,9007199254740993,{"\u00e9":2,"e\u0301":1}]"#)
    }

    @Test func deepSingletonArraysPreserveOneLeafEdit() throws {
        var source = "1"
        var target = "2"
        for _ in 0..<64 { source = "[\(source)]"; target = "[\(target)]" }
        try assertGeneratedPatch(source: source, target: target) { patch in
            #expect(patch.operations.count == 1)
        }
    }

    @Test func exhaustiveSmallDuplicateArraysRoundTrip() throws {
        var arrays = ["[]"]
        for length in 1...3 {
            for bits in 0..<(1 << length) {
                arrays.append("[" + (0..<length).map { String((bits >> $0) & 1) }.joined(separator: ",") + "]")
            }
        }
        for source in arrays {
            for target in arrays { try assertGeneratedPatch(source: source, target: target) }
        }
    }

    @Test func exhaustiveMatchingAnchorsAreExactAndMonotone() throws {
        var arrays: [[Int]] = [[]]
        for length in 1...5 {
            for bits in 0..<(1 << length) { arrays.append((0..<length).map { (bits >> $0) & 1 }) }
        }
        for source in arrays {
            for target in arrays {
                let result = try JSONPatchGenerator.ArrayMatching.align(NSArray(array: source), NSArray(array: target))
                // Independent small LCS oracle checks the search/backtracking,
                // not merely that the returned anchors happen to be equal.
                var lcs = Array(repeating: Array(repeating: 0, count: target.count + 1), count: source.count + 1)
                for i in source.indices {
                    for j in target.indices {
                        lcs[i + 1][j + 1] = source[i] == target[j] ? lcs[i][j] + 1 : max(lcs[i][j + 1], lcs[i + 1][j])
                    }
                }
                if !result.usedFallback {
                    #expect(result.prefix + result.matches.count + result.suffix == lcs[source.count][target.count])
                } else {
                    #expect(result.work <= JSONPatchGenerator.ArrayMatching.maximumWork)
                }
                var previousSource = result.prefix - 1
                var previousTarget = result.prefix - 1
                for match in result.matches {
                    #expect(match.source > previousSource && match.target > previousTarget)
                    #expect(source.indices.contains(match.source) && target.indices.contains(match.target))
                    #expect(source[match.source] == target[match.target])
                    previousSource = match.source
                    previousTarget = match.target
                }
            }
        }
    }
}
