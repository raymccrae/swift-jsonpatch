//
//  JSONPointerTests.swift
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

import Testing
@testable import JSONPatch

struct JSONPointerTests {

    func parent(_ string: String) -> String? {
        let pointer = try? JSONPointer(string: string)
        let parent = pointer?.parent
        return parent?.string
    }

    @Test func testParent() {
        #expect(parent("") == nil)
        #expect(parent("/a") == "")
        #expect(parent("/a/b") == "/a")
        #expect(parent("/a/b/c") == "/a/b")
        #expect(parent("/") == "")
        #expect(parent("//") == "/")
        #expect(parent("///") == "//")
    }

    @Test func testArrayIndexFormat() {
        #expect(JSONPointer.isValidArrayIndex("-"))
        #expect(!JSONPointer.isValidArrayIndex("--"))
        #expect(JSONPointer.isValidArrayIndex("0"))
        #expect(JSONPointer.isValidArrayIndex("1"))
        #expect(JSONPointer.isValidArrayIndex("10"))
        #expect(!JSONPointer.isValidArrayIndex("00"))
    }

    @Test func testValidEscapes() throws {
        let slash = try JSONPointer(string: "/a~1b")
        #expect(slash.lastComponent == "a/b")
        #expect(slash.string == "/a~1b")

        let tilde = try JSONPointer(string: "/a~0b")
        #expect(tilde.lastComponent == "a~b")
        #expect(tilde.string == "/a~0b")

        let orderedEscape = try JSONPointer(string: "/~01")
        #expect(orderedEscape.lastComponent == "~1")
        #expect(orderedEscape.string == "/~01")

        let literalTildeTwo = try JSONPointer(string: "/~02")
        #expect(literalTildeTwo.lastComponent == "~2")
        #expect(literalTildeTwo.string == "/~02")
    }

    @Test func testInvalidEscapes() {
        expectInvalidPointerSyntax("/a~2b")
        expectInvalidPointerSyntax("/a~")
        expectInvalidPointerSyntax("/a~~b")
        expectInvalidPointerSyntax("/a~01~")
        expectInvalidPointerSyntax("#/a~2b")
        expectInvalidPointerSyntax("#/a~")
    }

    @Test(arguments: ["", "ordinary_object_key", "e\u{0301}日本語👩‍💻", String(repeating: "abcdefgh", count: 128)])
    func testEscapeWithoutSpecialCharacters(_ input: String) {
        #expect(Array(JSONPointer.escape(input).unicodeScalars) == Array(input.unicodeScalars))
    }

    @Test(arguments: [
        "/a~\u{0301}2b",
        "/a~\u{0301}",
        "#/a%7E%CC%812b",
        "#/a%7E%CC%81"
    ])
    func testInvalidUnicodeEscapes(_ string: String) {
        expectInvalidPointerSyntax(string)
    }

    @Test(arguments: [
        ("/a~0\u{0301}b", "a~\u{0301}b", "/a~0\u{0301}b"),
        ("/a~1\u{0301}b", "a/\u{0301}b", "/a~1\u{0301}b"),
        ("#/a%7E0%CC%81b", "a~\u{0301}b", "/a~0\u{0301}b"),
        ("#/a%7E1%CC%81b", "a/\u{0301}b", "/a~1\u{0301}b"),
        ("/e\u{0301}👩‍💻~0~1", "e\u{0301}👩‍💻~/", "/e\u{0301}👩‍💻~0~1")
    ])
    func testValidUnicodeEscapes(_ input: String, _ expected: String, _ serialized: String) throws {
        let pointer = try JSONPointer(string: input)
        let component = try #require(pointer.lastComponent)
        #expect(Array(component.unicodeScalars) == Array(expected.unicodeScalars))
        #expect(Array(pointer.string.unicodeScalars) == Array(serialized.unicodeScalars))

        let reparsed = try JSONPointer(string: pointer.string)
        let reparsedComponent = try #require(reparsed.lastComponent)
        #expect(Array(reparsedComponent.unicodeScalars) == Array(expected.unicodeScalars))
    }

    private func expectInvalidPointerSyntax(_ string: String) {
        do {
            _ = try JSONPointer(string: string)
            Issue.record("Should have thrown JSONError.invalidPointerSyntax for \(string)")
        } catch {
            #expect(error as? JSONError == .invalidPointerSyntax)
        }
    }

}
