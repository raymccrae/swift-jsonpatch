//
//  ArrayTests.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 21/12/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation
import Testing
@testable import JSONPatch

struct ArrayTests {

    @Test func testLevel1DeepCopy() {
        let a = NSArray(array: ["a", "b", "c"])
        let b = a.deepMutableCopy()
        #expect(b.count == 3)
        #expect(b[0] as? String == "a")
        #expect(b[1] as? String == "b")
        #expect(b[2] as? String == "c")
    }

    @Test func testLevel2DeepCopy() {
        let a = NSMutableArray(array: ["a", "b", "c"])
        let b = NSMutableArray(array: [a])
        let c = b.deepMutableCopy()
        b.add("d")
        a.add("e")

        #expect(c.count == 1)
        guard let d = c[0] as? NSMutableArray else {
            Issue.record("Expected NSMutableArray")
            return
        }
        #expect(d.count == 3)
        #expect(d[0] as? String == "a")
        #expect(d[1] as? String == "b")
        #expect(d[2] as? String == "c")
    }

    @Test func testLevel3DeepCopy() {
        let a = NSMutableArray(array: ["a", "b", "c"])
        let b = NSMutableArray(array: [a])
        let c = NSMutableArray(array: [b])
        let d = c.deepMutableCopy()
        b.add("d")
        a.add("e")
        c.add("f")

        #expect(d.count == 1)
        guard let e = d[0] as? NSMutableArray else {
            Issue.record("Expected NSMutableArray")
            return
        }
        #expect(e.count == 1)
        guard let f = e[0] as? NSMutableArray else {
            Issue.record("Expected NSMutableArray")
            return
        }

        #expect(f.count == 3)
        #expect(f[0] as? String == "a")
        #expect(f[1] as? String == "b")
        #expect(f[2] as? String == "c")
    }

    @Test func testDictDeepCopy() {
        let dict = NSMutableDictionary(dictionary: ["a": "1"])
        let array = NSMutableArray(array: [dict])
        let copy = array.deepMutableCopy()
        array.add("b")
        dict["b"] = "2"

        #expect(copy.count == 1)
        guard let copyDict = copy[0] as? NSMutableDictionary else {
            Issue.record("Expected NSMutableDictionary")
            return
        }
        #expect(copyDict.count == 1)
        #expect(copyDict["a"] as? String == "1")
    }

    @Test func testStringDeepCopy() {
        let array = NSMutableArray(array: [NSMutableString(string: "1")])
        let copy = array.deepMutableCopy()
        (array[0] as! NSMutableString).setString("2")

        #expect(copy.count == 1)
        #expect(copy[0] as? String == "1")
    }

}
