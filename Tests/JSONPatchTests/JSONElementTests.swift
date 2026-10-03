//
//  JSONElementTests.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 17/11/2018.
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

struct JSONElementTests {

    @Test(arguments: [
        (#"[{"op":"add","path":"//added","value":2}]"#, #"{"":{"x":1,"source":3,"added":2},"x":9,"source":8}"#),
        (#"[{"op":"remove","path":"//x"}]"#, #"{"":{"source":3},"x":9,"source":8}"#),
        (#"[{"op":"replace","path":"//x","value":2}]"#, #"{"":{"x":2,"source":3},"x":9,"source":8}"#),
        (#"[{"op":"move","from":"//source","path":"//x"}]"#, #"{"":{"x":3},"x":9,"source":8}"#),
        (#"[{"op":"copy","from":"//source","path":"//x"}]"#, #"{"":{"x":3,"source":3},"x":9,"source":8}"#),
        (#"[{"op":"move","from":"//source","path":"/destination"}]"#, #"{"":{"x":1},"x":9,"source":8,"destination":3}"#),
        (#"[{"op":"move","from":"/source","path":"//x"}]"#, #"{"":{"x":8,"source":3},"x":9}"#),
        (#"[{"op":"copy","from":"/source","path":"//x"}]"#, #"{"":{"x":8,"source":3},"x":9,"source":8}"#)
    ])
    func testMutationsBeneathEmptyProperty(_ patchJSON: String, _ expectedJSON: String) throws {
        let patch = try JSONPatch(data: Data(patchJSON.utf8))
        let expected = try JSONSerialization.jsonElement(with: Data(expectedJSON.utf8), options: [])
        for options: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
            var element = try JSONSerialization.jsonElement(
                with: Data(#"{"":{"x":1,"source":3},"x":9,"source":8}"#.utf8), options: options)
            try element.apply(patch: patch)
            #expect(element == expected)
        }
    }

    @Test(arguments: [false, true])
    func testNestedEmptyPropertyMutation(_ relative: Bool) throws {
        let patchJSON = relative
            ? #"[{"op":"replace","path":"/x","value":2}]"#
            : #"[{"op":"replace","path":"/outer///x","value":2}]"#
        let patch = try JSONPatch(data: Data(patchJSON.utf8))
        let expected = try JSONSerialization.jsonElement(
            with: Data(#"{"outer":{"":{"":{"x":2},"x":7},"x":8},"x":9}"#.utf8), options: [])
        let applyOptions: [JSONPatch.ApplyOption] = relative
            ? [.relative(to: try JSONPointer(string: "/outer//"))] : []
        for options: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
            var element = try JSONSerialization.jsonElement(
                with: Data(#"{"outer":{"":{"":{"x":1},"x":7},"x":8},"x":9}"#.utf8), options: options)
            try element.apply(patch: patch, options: applyOptions)
            #expect(element == expected)
        }
    }

    @Test(arguments: ["/", "//nested"])
    func testRelativeMutationBeneathEmptyProperty(_ relativePath: String) throws {
        let patch = try JSONPatch(data: Data(#"[{"op":"replace","path":"/x","value":2}]"#.utf8))
        let json = relativePath == "/"
            ? #"{"":{"x":1},"x":9}"#
            : #"{"":{"nested":{"x":1}},"nested":{"x":8},"x":9}"#
        let expectedJSON = relativePath == "/"
            ? #"{"":{"x":2},"x":9}"#
            : #"{"":{"nested":{"x":2}},"nested":{"x":8},"x":9}"#
        let expected = try JSONSerialization.jsonElement(with: Data(expectedJSON.utf8), options: [])
        for options: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
            var element = try JSONSerialization.jsonElement(with: Data(json.utf8), options: options)
            try element.apply(patch: patch, options: [.relative(to: JSONPointer(string: relativePath))])
            #expect(element == expected)
        }
    }

    @Test(arguments: [
        (#"{"a":1}"#, "/a/x"),
        (#"{"a":"text"}"#, "/a/x"),
        (#"{"a":true}"#, "/a/x"),
        (#"{"a":null}"#, "/a/x"),
        (#"{"a":{"b":1}}"#, "/a/b/x"),
        (#"{"a":[null]}"#, "/a/0/x"),
        ("1", "/x"),
        (#""text""#, "/x"),
        ("true", "/x"),
        ("null", "/x")
    ])
    func testMutationThroughNoncontainerParent(_ json: String, _ path: String) throws {
        let pointer = try JSONPointer(string: path)
        let root = try JSONPointer(string: "")
        let target = try JSONPointer(string: "/target")
        let operations: [JSONPatch.Operation] = [
            .add(path: pointer, value: JSONElement(2)),
            .remove(path: pointer),
            .replace(path: pointer, value: JSONElement(2)),
            .copy(from: root, path: pointer),
            .move(from: pointer, path: target)
        ]

        for readingOptions: JSONSerialization.ReadingOptions in [[.fragmentsAllowed], [.fragmentsAllowed, .mutableContainers]] {
            for operation in operations {
                var element = try JSONSerialization.jsonElement(with: Data(json.utf8), options: readingOptions)
                let original = try element.copy()
                #expect(throws: JSONError.referencesNonexistentValue) {
                    try element.apply(operation)
                }
                #expect(element == original)
            }
        }
    }

    @Test(arguments: ["1", #""text""#, "true", "null"])
    func testMoveDestinationThroughNoncontainerParent(_ parentJSON: String) throws {
        for readingOptions: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
            var element = try JSONSerialization.jsonElement(
                with: Data("{\"source\":2,\"a\":\(parentJSON)}".utf8), options: readingOptions)
            let originalParent = try element.evaluate(pointer: JSONPointer(string: "/a"))
            #expect(throws: JSONError.referencesNonexistentValue) {
                try element.move(from: JSONPointer(string: "/source"), to: JSONPointer(string: "/a/x"))
            }
            // A move may remove its source before failing at the destination.
            #expect(try element.evaluate(pointer: JSONPointer(string: "/a")) == originalParent)
        }
    }

    @Test(arguments: ["/a", "/a/x"])
    func testRelativeMutationThroughNoncontainerParent(_ path: String) throws {
        for readingOptions: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
            var element = try JSONSerialization.jsonElement(with: Data(#"{"a":null}"#.utf8), options: readingOptions)
            let original = try element.copy()
            let patch = try JSONPatch(data: Data(#"[{"op":"add","path":"/x","value":2}]"#.utf8))
            #expect(throws: JSONError.referencesNonexistentValue) {
                try element.apply(patch: patch, options: [.relative(to: JSONPointer(string: path))])
            }
            #expect(element == original)
        }
    }

    @Test(arguments: [
        (#"{"value":1}"#, "/value", "2", "1"),
        (#"{"value":{"a":1}}"#, "/value", #"{"a":2}"#, #"{"a":1}"#),
        (#"{"value":[1,2]}"#, "/value", "[1,3]", "[1,2]"),
        (#"{"value":null}"#, "/value", "1", "null"),
        (#"{"a":1}"#, "", #"{"a":2}"#, #"{"a":1}"#)
    ])
    func testMismatchErrorPayload(_ json: String, _ path: String, _ expectedJSON: String, _ foundJSON: String) throws {
        let element = try JSONSerialization.jsonElement(with: Data(json.utf8), options: [])
        let expected = try JSONSerialization.jsonElement(with: Data(expectedJSON.utf8), options: [.fragmentsAllowed])
        let actual = try JSONSerialization.jsonElement(with: Data(foundJSON.utf8), options: [.fragmentsAllowed])

        do {
            try element.test(value: expected, at: JSONPointer(string: path))
            Issue.record("Expected JSONError.patchTestFailed")
        } catch JSONError.patchTestFailed(let errorPath, let errorExpected, let errorFound) {
            #expect(errorPath == path)
            #expect(try JSONElement(any: errorExpected.jsonObject()) == expected)
            let found = try #require(errorFound)
            #expect(try JSONElement(any: found.jsonObject()) == actual)
            if actual == .null {
                #expect(try found.jsonObject() is NSNull)
            }
        }
    }

    @Test func testMissingPathErrorPayload() throws {
        let element = try JSONSerialization.jsonElement(with: Data(#"{"value":1}"#.utf8), options: [])
        do {
            try element.test(value: JSONElement(2), at: JSONPointer(string: "/missing"))
            Issue.record("Expected JSONError.patchTestFailed")
        } catch JSONError.patchTestFailed(let path, let expected, let found) {
            #expect(path == "/missing")
            #expect(try JSONElement(any: expected.jsonObject()) == JSONElement(2))
            #expect(found == nil)
        }
    }

    @Test(arguments: [
        (#"{"value":1}"#, "/value", "1"),
        (#"{"value":null}"#, "/value", "null"),
        (#"{"value":1}"#, "", #"{"value":1}"#)
    ])
    func testMatchingValues(_ json: String, _ path: String, _ expectedJSON: String) throws {
        let element = try JSONSerialization.jsonElement(with: Data(json.utf8), options: [])
        let expected = try JSONSerialization.jsonElement(with: Data(expectedJSON.utf8), options: [.fragmentsAllowed])
        try element.test(value: expected, at: JSONPointer(string: path))
    }

    @Test(arguments: [
        (#"{"a":1}"#, "", "/backup", #"{"a":1,"backup":{"a":1}}"#),
        (#"{"a":{"value":1}}"#, "", "/a/backup", #"{"a":{"value":1,"backup":{"a":{"value":1}}}}"#),
        (#"[1,2]"#, "", "/-", #"[1,2,[1,2]]"#),
        (#"{"a":1,"backup":2}"#, "", "/backup", #"{"a":1,"backup":{"a":1,"backup":2}}"#),
        (#"{"a":1}"#, "", "", #"{"a":1}"#),
        (#"{"a":{"value":1}}"#, "/a", "", #"{"value":1}"#)
    ])
    func testCopyPaths(_ json: String, _ source: String, _ destination: String, _ expectedJSON: String) throws {
        let expected = try JSONSerialization.jsonElement(with: Data(expectedJSON.utf8), options: [])
        for options: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
            var element = try JSONSerialization.jsonElement(with: Data(json.utf8), options: options)
            try element.copy(from: JSONPointer(string: source), to: JSONPointer(string: destination))
            #expect(element == expected)
        }
    }

    @Test func testRootCopyIsIndependent() throws {
        var element = try JSONSerialization.jsonElement(
            with: Data(#"{"object":{"value":1},"items":[{"value":2}]}"#.utf8),
            options: [.mutableContainers])
        try element.copy(from: JSONPointer(string: ""), to: JSONPointer(string: "/backup"))

        try element.replace(value: JSONElement(3), to: JSONPointer(string: "/object/value"))
        try element.replace(value: JSONElement(4), to: JSONPointer(string: "/items/0/value"))
        #expect(try element.evaluate(pointer: JSONPointer(string: "/backup/object/value")) == JSONElement(1))
        #expect(try element.evaluate(pointer: JSONPointer(string: "/backup/items/0/value")) == JSONElement(2))

        try element.replace(value: JSONElement(5), to: JSONPointer(string: "/backup/object/value"))
        try element.replace(value: JSONElement(6), to: JSONPointer(string: "/backup/items/0/value"))
        #expect(try element.evaluate(pointer: JSONPointer(string: "/object/value")) == JSONElement(3))
        #expect(try element.evaluate(pointer: JSONPointer(string: "/items/0/value")) == JSONElement(4))
    }

    @Test(arguments: [("/missing", "/backup"), ("", "/missing/backup")])
    func testCopyMissingPath(_ source: String, _ destination: String) throws {
        var element = try JSONSerialization.jsonElement(with: Data(#"{"a":1}"#.utf8), options: [.mutableContainers])
        let original = try element.copy()
        do {
            try element.copy(from: JSONPointer(string: source), to: JSONPointer(string: destination))
            Issue.record("Expected JSONError.referencesNonexistentValue")
        } catch {
            #expect(error as? JSONError == .referencesNonexistentValue)
        }
        #expect(element == original)
    }

    @Test(arguments: [
        (#"{"a":{"b":[],"value":1}}"#, "/a", "/a/b/-"),
        (#"{"a":{"b":[],"value":1}}"#, "/a", "/a/b"),
        (#"{"items":[{"child":1}]}"#, "/items/0", "/items/0/child"),
        (#"{"a":1}"#, "", "/backup"),
        (#"{"a/b":{"child":1}}"#, "/a~1b", "/a~1b/child")
    ])
    func testRecursiveMovePreservesDocument(_ json: String, _ source: String, _ destination: String) throws {
        let document = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.mutableContainers])
        var element = try JSONElement(any: document)
        let original = try element.copy()
        let from = try JSONPointer(string: source)
        let to = try JSONPointer(string: destination)

        do {
            try element.move(from: from, to: to)
            Issue.record("Expected recursive move to throw JSONError.invalidPatchFormat")
        } catch {
            #expect(error as? JSONError == .invalidPatchFormat)
        }

        #expect(element == original)
        #expect(try JSONElement(any: document) == original)
    }

    @Test(arguments: [
        (#"{"a":1}"#, "/a", "/ab", #"{"ab":1}"#),
        (#"{"a":{"b":1}}"#, "/a", "/a", #"{"a":{"b":1}}"#),
        (#"{"a":1}"#, "", "", #"{"a":1}"#),
        (#"{"a":{"b":1}}"#, "/a", "", #"{"b":1}"#),
        (#"[1,2,3]"#, "/0", "/2", #"[2,3,1]"#),
        (#"[1,2,3]"#, "/1", "/1", #"[1,2,3]"#)
    ])
    func testValidMovePaths(_ json: String, _ source: String, _ destination: String, _ expectedJSON: String) throws {
        var element = try JSONSerialization.jsonElement(with: Data(json.utf8), options: [.mutableContainers])
        let expected = try JSONSerialization.jsonElement(with: Data(expectedJSON.utf8), options: [])
        try element.move(from: JSONPointer(string: source), to: JSONPointer(string: destination))
        #expect(element == expected)
    }

    @Test(arguments: ["", "/~"])
    func testMoveBetweenDistinctUnicodeProperties(_ suffix: String) throws {
        let composed = "\u{00e9}" + suffix
        let decomposed = "e\u{0301}" + suffix
        for mutable in [false, true] {
            // Construct Foundation keys directly so Swift Dictionary cannot merge them.
            let document = NSMutableDictionary()
            document.setObject(NSNumber(value: 1), forKey: composed as NSString)
            document.setObject(NSMutableDictionary(), forKey: decomposed as NSString)
            #expect(document.count == 2)
            var element: JSONElement = mutable
                ? .mutableObject(value: document)
                : .object(value: document.copy() as! NSDictionary)

            try element.move(
                from: JSONPointer(string: "/" + JSONPointer.escape(composed)),
                to: JSONPointer(string: "/" + JSONPointer.escape(decomposed) + "/x"))

            let result = try #require(element.rawValue as? NSDictionary)
            #expect(result.count == 1)
            #expect(result[composed] == nil)
            let destination = try #require(result[decomposed] as? NSDictionary)
            #expect(destination["x"] as? NSNumber == NSNumber(value: 1))
        }
    }

    @Test(arguments: ["\u{00e9}", "e\u{0301}", "\u{00e9}/~", "e\u{0301}/~"])
    func testRecursiveUnicodeMovePreservesDocument(_ key: String) throws {
        let child = NSMutableDictionary()
        child.setObject(NSNumber(value: 1), forKey: "value" as NSString)
        let document = NSMutableDictionary()
        document.setObject(child, forKey: key as NSString)
        var element = JSONElement.mutableObject(value: document)
        let source = try JSONPointer(string: "/" + JSONPointer.escape(key))
        let destination = try JSONPointer(string: source.string + "/x")

        #expect(throws: JSONError.invalidPatchFormat) {
            try element.move(from: source, to: destination)
        }
        #expect(document.count == 1)
        #expect(document[key] as? NSDictionary === child)
        #expect(child.count == 1)
        #expect(child["value"] as? NSNumber == NSNumber(value: 1))
    }

    @Test func testNumericEquality() throws {
        let boolFalse = try JSONElement(any: NSNumber(value: false))
        let int0 = try JSONElement(any: NSNumber(value: 0))
        let double0 = try JSONElement(any: NSNumber(value: 0.0))
        let int42 = try JSONElement(any: NSNumber(value: 42))
        let double42 = try JSONElement(any: NSNumber(value: 42.0))
        let double42_5 = try JSONElement(any: NSNumber(value: 42.5))

        #expect(boolFalse != int0)
        #expect(boolFalse != double0)

        #expect(int0 == double0)
        #expect(int42 == double42)

        #expect(int42 != double42_5)
    }

    @Test func testDecode() throws {
        let json = Data("""
        {
            "string": "hello",
            "int": 42,
            "double": 4.2,
            "boolean": true,
            "array": [1, 2, 3],
            "object": {"a": "b"}
        }
        """.utf8)

        let decoder = JSONDecoder()
        let jsonDecoded = try decoder.decode(JSONElement.self, from: json)
        let jsonSerialization = try JSONSerialization.jsonElement(with: json, options: [])

        #expect(jsonDecoded == jsonSerialization)
    }

    @Test func testCopy() throws {
        do {
            let int = try JSONElement(any: NSNumber(value: 0))
            let string = try JSONElement(any: "Test")
            let array = try JSONElement(any: [1, 2, 3])
            let dict = try JSONElement(any: ["Test": 1])

            let _ = try int.copy()
            let _ = try string.copy()
            let _ = try array.copy()
            let _ = try dict.copy()
        } catch {
            Issue.record("Should not throw an exception, but caught: \(error)")
        }
    }

}
