//
//  JSONPatchTests.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import XCTest
@testable import JSONPatch

class JSONPatchTests: XCTestCase {

    func evaluate(path: String, on json: JSONElement) -> JSONElement? {
        guard let ptr = try? JSONPointer(string: path) else {
            return nil
        }
        return try? json.evaluate(pointer: ptr)
    }

    // This test is based on the sample given in section 5 of RFC 6901
    // https://tools.ietf.org/html/rfc6901
    func testExample() throws {
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

        XCTAssertEqual(evaluate(path: "", on: json) , json)
        XCTAssertEqual(evaluate(path: "/foo", on: json) , .array(value: ["bar", "baz"]))
        XCTAssertEqual(evaluate(path: "/foo/0", on: json) , .string(value: "bar"))
        XCTAssertEqual(evaluate(path: "/", on: json) , .number(value: NSNumber(value: 0)))
        XCTAssertEqual(evaluate(path: "/a~1b", on: json) , .number(value: NSNumber(value: 1)))
        XCTAssertEqual(evaluate(path: "/c%d", on: json) , .number(value: NSNumber(value: 2)))
        XCTAssertEqual(evaluate(path: "/e^f", on: json) , .number(value: NSNumber(value: 3)))
        XCTAssertEqual(evaluate(path: "/g|h", on: json) , .number(value: NSNumber(value: 4)))
        XCTAssertEqual(evaluate(path: "/i\\j", on: json) , .number(value: NSNumber(value: 5)))
        XCTAssertEqual(evaluate(path: "/k\"l", on: json) , .number(value: NSNumber(value: 6)))
        XCTAssertEqual(evaluate(path: "/ ", on: json) , .number(value: NSNumber(value: 7)))
        XCTAssertEqual(evaluate(path: "/m~0n", on: json) , .number(value: NSNumber(value: 8)))
    }

    func testAdd() throws {
        let sample = """
        {
        "a": { "b": 1 },
        "z": [ 1, 2 ]
        }
        """

        let jsonObject = try JSONSerialization.jsonObject(with: Data(sample.utf8), options: [])
        var json = try JSONElement(any: jsonObject)

        let ptr = try JSONPointer(string: "/z/-")
        try json.add(value: .number(value: NSNumber(value: 4)), to: ptr)
        try json.add(value: .object(value: [:] as NSDictionary), to: ptr)
        print(json)
    }

}
