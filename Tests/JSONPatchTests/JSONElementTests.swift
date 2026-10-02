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
