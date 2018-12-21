//
//  ArrayTests.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 21/12/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import XCTest
@testable import JSONPatch

class ArrayTests: XCTestCase {

    func testLevel1DeepCopy() {
        let a = NSArray(array: ["a", "b", "c"])
        let b = a.deepMutableCopy()
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b[0] as? String, "a")
        XCTAssertEqual(b[1] as? String, "b")
        XCTAssertEqual(b[2] as? String, "c")
    }

    func testLevel2DeepCopy() {
        let a = NSMutableArray(array: ["a", "b", "c"])
        let b = NSMutableArray(array: [a])
        let c = b.deepMutableCopy()
        b.add("d")
        a.add("e")

        XCTAssertEqual(c.count, 1)
        guard let d = c[0] as? NSMutableArray else {
            XCTFail()
            return
        }
        XCTAssertEqual(d.count, 3)
        XCTAssertEqual(d[0] as? String, "a")
        XCTAssertEqual(d[1] as? String, "b")
        XCTAssertEqual(d[2] as? String, "c")
    }

    func testLevel3DeepCopy() {
        let a = NSMutableArray(array: ["a", "b", "c"])
        let b = NSMutableArray(array: [a])
        let c = NSMutableArray(array: [b])
        let d = c.deepMutableCopy()
        b.add("d")
        a.add("e")
        c.add("f")

        XCTAssertEqual(d.count, 1)
        guard let e = d[0] as? NSMutableArray else {
            XCTFail()
            return
        }
        XCTAssertEqual(e.count, 1)
        guard let f = e[0] as? NSMutableArray else {
            XCTFail()
            return
        }

        XCTAssertEqual(f.count, 3)
        XCTAssertEqual(f[0] as? String, "a")
        XCTAssertEqual(f[1] as? String, "b")
        XCTAssertEqual(f[2] as? String, "c")
    }

    func testDictDeepCopy() {
        let dict = NSMutableDictionary(dictionary: ["a": "1"])
        let array = NSMutableArray(array: [dict])
        let copy = array.deepMutableCopy()
        array.add("b")
        dict["b"] = "2"

        XCTAssertEqual(copy.count, 1)
        guard let copyDict = copy[0] as? NSMutableDictionary else {
            XCTFail()
            return
        }
        XCTAssertEqual(copyDict.count, 1)
        XCTAssertEqual(copyDict["a"] as? String, "1")
    }

    func testStringDeepCopy() {
        let array = NSMutableArray(array: [NSMutableString(string: "1")])
        let copy = array.deepMutableCopy()
        (array[0] as! NSMutableString).setString("2")

        XCTAssertEqual(copy.count, 1)
        XCTAssertEqual(copy[0] as? String, "1")
    }

}
