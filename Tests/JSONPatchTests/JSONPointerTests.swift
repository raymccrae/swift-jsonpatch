//
//  JSONPointerTests.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
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
        XCTAssertEqual(parent("/a"), "/")
        XCTAssertEqual(parent("/a/b"), "/a")
        XCTAssertEqual(parent("/a/b/c"), "/a/b")
        XCTAssertEqual(parent("/"), "")
        XCTAssertEqual(parent("//"), "/")
        XCTAssertEqual(parent("///"), "//")
    }

}
