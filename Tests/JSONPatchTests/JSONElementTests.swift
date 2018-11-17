//
//  JSONElementTests.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 17/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import XCTest
@testable import JSONPatch

class JSONElementTests: XCTestCase {

    func testNumericEquality() throws {
        let boolFalse = try JSONElement(any: NSNumber(value: false))
        let int0 = try JSONElement(any: NSNumber(value: 0))
        let double0 = try JSONElement(any: NSNumber(value: 0.0))
        let int42 = try JSONElement(any: NSNumber(value: 42))
        let double42 = try JSONElement(any: NSNumber(value: 42.0))
        let double42_5 = try JSONElement(any: NSNumber(value: 42.5))

        XCTAssertNotEqual(boolFalse, int0)
        XCTAssertNotEqual(boolFalse, double0)

        XCTAssertEqual(int0, double0)
        XCTAssertEqual(int42, double42)

        XCTAssertNotEqual(int42, double42_5)
    }

}
