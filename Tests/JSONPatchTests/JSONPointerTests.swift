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

import XCTest
@testable import JSONPatch

class JSONPointerTests: XCTestCase {

    func parent(_ string: String) -> String? {
        let pointer = try? JSONPointer(string: string)
        let parent = pointer?.parent
        return parent?.string
    }

    func testParent() {
        XCTAssertNil(parent(""))
        XCTAssertEqual(parent("/a"), "")
        XCTAssertEqual(parent("/a/b"), "/a")
        XCTAssertEqual(parent("/a/b/c"), "/a/b")
        XCTAssertEqual(parent("/"), "")
        XCTAssertEqual(parent("//"), "/")
        XCTAssertEqual(parent("///"), "//")
    }

    func testArrayIndexFormat() {
        XCTAssertTrue(JSONPointer.isValidArrayIndex("-"))
        XCTAssertFalse(JSONPointer.isValidArrayIndex("--"))
        XCTAssertTrue(JSONPointer.isValidArrayIndex("0"))
        XCTAssertTrue(JSONPointer.isValidArrayIndex("1"))
        XCTAssertTrue(JSONPointer.isValidArrayIndex("10"))
        XCTAssertFalse(JSONPointer.isValidArrayIndex("00"))
    }

}
