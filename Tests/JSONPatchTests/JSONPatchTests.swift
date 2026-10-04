//
//  JSONPatchTests.swift
//  JSONPatchTests
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
import Testing
@testable import JSONPatch

struct OperationValueFixture: Sendable {
    let operation: String
    let destination: String
    let path: String
    let mutationPath: String
    let value: String
    let source: Data
    let expected: Data
    let patchData: Data
    let arrayValue: Bool

    init(operation: String, destination: String, arrayValue: Bool) {
        self.operation = operation
        self.destination = destination
        self.arrayValue = arrayValue
        value = arrayValue ? #"[{"items":[]}]"# : #"{"items":[]}"#
        let changedValue = arrayValue ? #"[{"items":[1]}]"# : #"{"items":[1]}"#
        switch destination {
        case "object":
            path = "/a"
            source = Data((operation == "add" ? "{}" : #"{"a":0}"#).utf8)
            expected = Data("{\"a\":\(changedValue)}".utf8)
        case "array":
            path = "/0"
            source = Data((operation == "add" ? "[]" : "[0]").utf8)
            expected = Data("[\(changedValue)]".utf8)
        default:
            path = ""
            source = Data("{}".utf8)
            expected = Data(changedValue.utf8)
        }
        mutationPath = path + (arrayValue ? "/0/items/-" : "/items/-")
        patchData = Data("[{\"op\":\"\(operation)\",\"path\":\"\(path)\",\"value\":\(value)},{\"op\":\"add\",\"path\":\"\(mutationPath)\",\"value\":1}]".utf8)
    }

    static var cases: [OperationValueFixture] {
        ["add", "replace"].flatMap { operation in
            ["object", "array", "root"].flatMap { destination in
                [false, true].map { OperationValueFixture(operation: operation, destination: destination, arrayValue: $0) }
            }
        }
    }

    func patches() throws -> [JSONPatch] {
        let mutableJSON = try JSONSerialization.jsonObject(with: patchData, options: [.mutableContainers]) as! NSArray
        // Supply mutable containers directly, including an array nested inside an object.
        let items = NSMutableArray()
        let object = NSMutableDictionary()
        object["items"] = items
        let suppliedValue: JSONElement = arrayValue ? .mutableArray(value: NSMutableArray(object: object)) : .mutableObject(value: object)
        let firstOperation: JSONPatch.Operation = operation == "add"
            ? .add(path: try JSONPointer(string: path), value: suppliedValue)
            : .replace(path: try JSONPointer(string: path), value: suppliedValue)
        return [
            try JSONDecoder().decode(JSONPatch.self, from: patchData),
            try JSONPatch(data: patchData),
            try JSONPatch(jsonArray: mutableJSON),
            JSONPatch(operations: [firstOperation, .add(path: try JSONPointer(string: mutationPath), value: JSONElement(1))])
        ]
    }
}

struct JSONPatchTests {

    @Test(arguments: OperationValueFixture.cases)
    func testApplicationPreservesOperationValues(_ fixture: OperationValueFixture) throws {
        let expected = try JSONSerialization.jsonElement(with: fixture.expected, options: [])
        let expectedData = try JSONSerialization.data(withJSONObject: expected.rawValue, options: [.sortedKeys])

        for patch in try fixture.patches() {
            let serialized = try patch.data(options: [.sortedKeys])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(patch)
            for options: [JSONPatch.ApplyOption] in [[], [.applyOnCopy]] {
                for _ in 0..<2 {
                    let resultData = try patch.apply(to: fixture.source, writingOptions: [.sortedKeys], applyingOptions: options)
                    #expect(resultData == expectedData)

                    let source = try JSONSerialization.jsonObject(with: fixture.source, options: [.mutableContainers])
                    var result = try JSONElement(any: patch.apply(to: source, options: options))
                    #expect(result == expected)
                    if options.contains(.applyOnCopy) {
                        #expect(try JSONElement(any: source) == JSONSerialization.jsonElement(with: fixture.source, options: []))
                    }
                    try result.add(value: JSONElement(2), to: JSONPointer(string: fixture.mutationPath))

                    // The public single-operation entry point must isolate values too.
                    var element = try JSONSerialization.jsonElement(with: fixture.source, options: [.mutableContainers])
                    for operation in patch.operations {
                        try element.apply(operation)
                    }
                    #expect(element == expected)
                    #expect(try patch.data(options: [.sortedKeys]) == serialized)
                    #expect(try encoder.encode(patch) == encoded)
                }
            }
        }
    }

    @Test(arguments: OperationValueFixture.cases)
    func testFailedApplicationPreservesOperationValues(_ fixture: OperationValueFixture) throws {
        let expected = try JSONSerialization.jsonElement(with: fixture.expected, options: [])
        let original = try JSONSerialization.jsonElement(with: fixture.source, options: [])
        for successfulPatch in try fixture.patches() {
            // Fail after inserting a constant and mutating a container nested inside it.
            let patch = JSONPatch(operations: successfulPatch.operations + [.remove(path: try JSONPointer(string: "/missing"))])
            let serialized = try patch.data(options: [.sortedKeys])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(patch)
            for options: [JSONPatch.ApplyOption] in [[], [.applyOnCopy]] {
                for _ in 0..<2 {
                    #expect(throws: JSONError.referencesNonexistentValue) {
                        _ = try patch.apply(to: fixture.source, applyingOptions: options)
                    }
                    let source = try JSONSerialization.jsonObject(with: fixture.source, options: [.mutableContainers])
                    #expect(throws: JSONError.referencesNonexistentValue) {
                        _ = try patch.apply(to: source, options: options)
                    }
                    let expectedSource = options.contains(.applyOnCopy) || fixture.destination == "root" ? original : expected
                    #expect(try JSONElement(any: source) == expectedSource)

                    var element = try JSONSerialization.jsonElement(with: fixture.source, options: [.mutableContainers])
                    #expect(throws: JSONError.referencesNonexistentValue) {
                        try element.apply(patch: patch)
                    }
                    #expect(element == expected)
                    #expect(try patch.data(options: [.sortedKeys]) == serialized)
                    #expect(try encoder.encode(patch) == encoded)
                }
            }
        }
    }

    @Test func testInvalidScalarParentStopsPatch() throws {
        let json = Data(#"{"a":1}"#.utf8)
        let original = try JSONSerialization.jsonElement(with: json, options: [])
        let patch = try JSONPatch(data: Data(#"[{"op":"add","path":"/a/x","value":2},{"op":"add","path":"/later","value":true}]"#.utf8))
        for readingOptions: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
            let document = try JSONSerialization.jsonObject(with: json, options: readingOptions)
            #expect(throws: JSONError.referencesNonexistentValue) {
                _ = try patch.apply(to: document)
            }
            #expect(try JSONElement(any: document) == original)
        }
    }

    @Test(arguments: [false, true])
    func testMismatchPreservesPayloadAndStopsPatch(_ ignoreNonexistentValues: Bool) throws {
        let json = Data(#"{"value":1}"#.utf8)
        let document = try JSONSerialization.jsonObject(with: json, options: [.mutableContainers])
        let original = try JSONSerialization.jsonElement(with: json, options: [])
        let patch = try JSONPatch(data: Data(#"[{"op":"test","path":"/value","value":2},{"op":"add","path":"/later","value":true}]"#.utf8))
        let options: [JSONPatch.ApplyOption] = ignoreNonexistentValues ? [.ignoreNonexistentValues] : []

        do {
            _ = try patch.apply(to: document, options: options)
            Issue.record("Expected JSONError.patchTestFailed")
        } catch JSONError.patchTestFailed(let path, let expected, let found) {
            #expect(path == "/value")
            #expect(try JSONElement(any: expected.jsonObject()) == JSONElement(2))
            let actual = try #require(found)
            #expect(try JSONElement(any: actual.jsonObject()) == JSONElement(1))
        }

        #expect(try JSONElement(any: document) == original)
    }

    @Test(arguments: [false, true])
    func testRootCopyPatch(_ ignoreNonexistentValues: Bool) throws {
        let document = try JSONSerialization.jsonObject(with: Data(#"{"a":1}"#.utf8), options: [.mutableContainers])
        let patch = try JSONPatch(data: Data(#"[{"op":"copy","from":"","path":"/backup"}]"#.utf8))
        let options: [JSONPatch.ApplyOption] = ignoreNonexistentValues ? [.ignoreNonexistentValues] : []
        let result = try JSONElement(any: patch.apply(to: document, options: options))
        let expected = try JSONSerialization.jsonElement(with: Data(#"{"a":1,"backup":{"a":1}}"#.utf8), options: [])
        #expect(result == expected)
    }

    @Test(arguments: [false, true])
    func testRecursiveMoveStopsPatch(_ ignoreNonexistentValues: Bool) throws {
        let json = Data(#"{"a":{"b":[],"value":1}}"#.utf8)
        let document = try JSONSerialization.jsonObject(with: json, options: [.mutableContainers])
        let original = try JSONSerialization.jsonElement(with: json, options: [])
        let patch = try JSONPatch(data: Data(#"[{"op":"move","from":"/a","path":"/a/b/-"},{"op":"add","path":"/later","value":true}]"#.utf8))
        let options: [JSONPatch.ApplyOption] = ignoreNonexistentValues ? [.ignoreNonexistentValues] : []

        do {
            _ = try patch.apply(to: document, options: options)
            Issue.record("Expected recursive move to throw JSONError.invalidPatchFormat")
        } catch {
            #expect(error as? JSONError == .invalidPatchFormat)
        }

        #expect(try JSONElement(any: document) == original)
    }

    func evaluate(path: String, on json: JSONElement) -> JSONElement? {
        guard let ptr = try? JSONPointer(string: path) else {
            return nil
        }
        return try? json.evaluate(pointer: ptr)
    }

    // This test is based on the sample given in section 5 of RFC 6901
    // https://tools.ietf.org/html/rfc6901
    @Test func testExample() throws {
        let sample = """
        {
        "foo": ["bar", "baz"],
        "": 0,
        "a/b": 1,
        "c%d": 2,
        "e^f": 3,
        "g|h": 4,
        "i\\\\j": 5,
        "k\\"l": 6,
        " ": 7,
        "m~n": 8
        }
        """

        let jsonObject = try JSONSerialization.jsonObject(with: Data(sample.utf8), options: [])
        let json = try JSONElement(any: jsonObject)

        #expect(evaluate(path: "", on: json) == json)
        #expect(evaluate(path: "/foo", on: json) == .array(value: ["bar", "baz"]))
        #expect(evaluate(path: "/foo/0", on: json) == .string(value: "bar"))
        #expect(evaluate(path: "/", on: json) == .number(value: NSNumber(value: 0)))
        #expect(evaluate(path: "/a~1b", on: json) == .number(value: NSNumber(value: 1)))
        #expect(evaluate(path: "/c%d", on: json) == .number(value: NSNumber(value: 2)))
        #expect(evaluate(path: "/e^f", on: json) == .number(value: NSNumber(value: 3)))
        #expect(evaluate(path: "/g|h", on: json) == .number(value: NSNumber(value: 4)))
        #expect(evaluate(path: "/i\\j", on: json) == .number(value: NSNumber(value: 5)))
        #expect(evaluate(path: "/k\"l", on: json) == .number(value: NSNumber(value: 6)))
        #expect(evaluate(path: "/ ", on: json) == .number(value: NSNumber(value: 7)))
        #expect(evaluate(path: "/m~0n", on: json) == .number(value: NSNumber(value: 8)))

        #expect(evaluate(path: "#", on: json) == json)
        #expect(evaluate(path: "#/foo", on: json) == .array(value: ["bar", "baz"]))
        #expect(evaluate(path: "#/foo/0", on: json) == .string(value: "bar"))
        #expect(evaluate(path: "#/", on: json) == .number(value: NSNumber(value: 0)))
        #expect(evaluate(path: "#/a~1b", on: json) == .number(value: NSNumber(value: 1)))
        #expect(evaluate(path: "#/c%25d", on: json) == .number(value: NSNumber(value: 2)))
        #expect(evaluate(path: "#/e%5Ef", on: json) == .number(value: NSNumber(value: 3)))
        #expect(evaluate(path: "#/g%7Ch", on: json) == .number(value: NSNumber(value: 4)))
        #expect(evaluate(path: "#/i%5Cj", on: json) == .number(value: NSNumber(value: 5)))
        #expect(evaluate(path: "#/k%22l", on: json) == .number(value: NSNumber(value: 6)))
        #expect(evaluate(path: "#/%20", on: json) == .number(value: NSNumber(value: 7)))
        #expect(evaluate(path: "#/m~0n", on: json) == .number(value: NSNumber(value: 8)))
    }

    @Test func testOperationEquality() throws {
        let ptr = try JSONPointer(string: "")
        let oppa = JSONPatch.Operation.add(path: ptr, value: JSONElement(false))
        let oppb = JSONPatch.Operation.add(path: ptr, value: JSONElement(0))
        #expect(oppa != oppb)
    }

    @Test func testTopLevelFragments() throws {
        let ptr = try JSONPointer(string: "")
        let doc = Data("3".utf8)
        let op = JSONPatch.Operation.replace(path: ptr, value: JSONElement(false))
        let patch = JSONPatch(operations: [op])
        let result = try patch.apply(to: doc,
                                 readingOptions: [.allowFragments],
                                 writingOptions: [])
        #expect(String(data: result, encoding: .utf8) == "false")
    }

    @Test func testLargeJson() throws {
        let sourceURL = try TestResources.url(forResource: "bigexample1", withExtension: "json")
        let targetURL = try TestResources.url(forResource: "bigexample2", withExtension: "json")
        let patchURL = try TestResources.url(forResource: "bigpatch", withExtension: "json")

        let sourceData = try Data(contentsOf: sourceURL)
        let targetData = try Data(contentsOf: targetURL)
        let patchData = try Data(contentsOf: patchURL)

        var sourceElem = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let targetElem = try JSONSerialization.jsonElement(with: targetData, options: [.mutableContainers])

        let patch = try JSONPatch(data: patchData)
        try sourceElem.apply(patch: patch)
        #expect(sourceElem == targetElem)
    }

    @Test func testLargeJSONPerformance() throws {
        let sourceURL = try TestResources.url(forResource: "bigexample1", withExtension: "json")
        let patchURL = try TestResources.url(forResource: "bigpatch", withExtension: "json")

        let sourceData = try Data(contentsOf: sourceURL)
        let patchData = try Data(contentsOf: patchURL)

        // Note: Swift Testing doesn't have a direct equivalent to measure(),
        // but we can still run the code to ensure it works
        let patch = try JSONPatch(data: patchData)
        let _ = try patch.apply(to: sourceData)
    }

    @Test func testPatchRelative() throws {
        let source = """
        {"a": {}}
        """
        let patch = Data("""
        [{ "op": "add", "path": "/b", "value": "qux" }]
        """.utf8)

        let p = try JSONPatch(data: patch)
        let s = try JSONSerialization.jsonObject(with: Data(source.utf8), options: [])
        let applied = try p.apply(to: s, options: [.relative(to: try JSONPointer(string: "/a"))])
        #expect(applied as? NSDictionary == ["a":["b":"qux"]] as NSDictionary)
    }

    @Test func testNonexistentValue() throws {
        let objectData = Data("""
        {
            "prop1": "Value1",
            "prop2": "Value2"
        }
        """.utf8)
        
        let patchData = Data("""
        [
            { "op": "replace", "path": "/prop3", "value": "Value3" }
        ]
        """.utf8)
        
        let patch = try JSONDecoder().decode(JSONPatch.self, from: patchData)
        
        do {
            let _ = try patch.apply(to: objectData)
            Issue.record("Should have thrown a nonExistentValue error")
        } catch {
            if let error = error as? JSONError, error == .referencesNonexistentValue {
                // Succeeded
            } else {
                Issue.record("Should have thrown JSONError.referencesNonexistentValue, but throwed: \(error)")
            }
        }
    }
    
    @Test func testIgnoreNonexistentValue() throws {
        let objectData = Data("""
        {
            "prop1": "Value1",
            "prop2": "Value2"
        }
        """.utf8)
        
        let patchData = Data("""
        [
            { "op": "replace", "path": "/prop3", "value": "Value3" }
        ]
        """.utf8)
        
        let patch = try JSONDecoder().decode(JSONPatch.self, from: patchData)
        
        do {
            let _ = try patch.apply(to: objectData, applyingOptions: [.ignoreNonexistentValues])
            // Succeeded
        } catch {
            Issue.record("Should not have thrown JSONError.referencesNonexistentValue, throwed: \(error)")
        }
    }
}

struct OperationPointerSyntaxTests {
    @Test(arguments: ["add", "remove", "replace", "move", "copy", "test"])
    func rejectsFragmentPaths(op: String) throws {
        for path in ["#", "#/x"] {
            try assertRejected(["op": op, "path": path, "from": "/x", "value": 2])
        }
    }

    @Test(arguments: ["move", "copy"])
    func rejectsFragmentSources(op: String) throws {
        for from in ["#", "#/x"] {
            try assertRejected(["op": op, "path": "/x", "from": from])
        }
    }

    @Test(arguments: ["add", "remove", "replace", "move", "copy", "test"])
    func acceptsStringPointers(op: String) throws {
        for pointer in ["", "/", "/x", "/#", "/x#y"] {
            let object: NSDictionary = ["op": op, "path": pointer, "from": pointer, "value": 2]
            let operation = try JSONPatch.Operation(jsonObject: object)
            let data = try JSONSerialization.data(withJSONObject: [object])
            #expect(try JSONPatch(jsonArray: [object]).operations == [operation])
            #expect(try JSONPatch(data: data).operations == [operation])
            #expect(try JSONDecoder().decode(JSONPatch.self, from: data).operations == [operation])
            let operationData = try JSONSerialization.data(withJSONObject: object)
            #expect(try JSONDecoder().decode(JSONPatch.Operation.self, from: operationData) == operation)
        }
    }

    @Test func standalonePointersRetainFragmentSupport() throws {
        for fragment in ["#", "#/x"] {
            let pointer = try JSONPointer(string: fragment)
            #expect(pointer.string == String(fragment.dropFirst()))
            let data = try JSONEncoder().encode(fragment)
            #expect(try JSONDecoder().decode(JSONPointer.self, from: data) == pointer)
        }
    }

    private func assertRejected(_ object: NSDictionary) throws {
        #expect(throws: JSONError.invalidPointerSyntax) {
            _ = try JSONPatch.Operation(jsonObject: object)
        }
        #expect(throws: JSONError.invalidPointerSyntax) {
            _ = try JSONPatch(jsonArray: [object])
        }
        let data = try JSONSerialization.data(withJSONObject: [object])
        #expect(throws: JSONError.invalidPointerSyntax) {
            _ = try JSONPatch(data: data)
        }
        #expect(throws: JSONError.invalidPointerSyntax) {
            _ = try JSONDecoder().decode(JSONPatch.self, from: data)
        }
        let operationData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: JSONError.invalidPointerSyntax) {
            _ = try JSONDecoder().decode(JSONPatch.Operation.self, from: operationData)
        }
    }
}
