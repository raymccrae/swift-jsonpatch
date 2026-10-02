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

struct JSONPatchTests {

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

    private class BundleToken {}

    private static func testBundleURL(forResource name: String, withExtension ext: String?) -> URL {
        let bundle = Bundle(for: BundleToken.self)
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        } else {
            // Fallback to source directory
            let cwd = FileManager.default.currentDirectoryPath
            let sourceDir = URL(fileURLWithPath: cwd).appendingPathComponent("Tests").appendingPathComponent("JSONPatchTests")
            return sourceDir.appendingPathComponent(name).appendingPathExtension(ext ?? "")
        }
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
        let sourceURL = Self.testBundleURL(forResource: "bigexample1", withExtension: "json")
        let targetURL = Self.testBundleURL(forResource: "bigexample2", withExtension: "json")
        let patchURL = Self.testBundleURL(forResource: "bigpatch", withExtension: "json")

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
        let sourceURL = Self.testBundleURL(forResource: "bigexample1", withExtension: "json")
        let patchURL = Self.testBundleURL(forResource: "bigpatch", withExtension: "json")

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
