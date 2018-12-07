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

    func testDecode() throws {
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

        XCTAssertEqual(jsonDecoded, jsonSerialization)
    }

}
