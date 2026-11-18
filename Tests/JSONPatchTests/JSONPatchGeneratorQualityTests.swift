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
