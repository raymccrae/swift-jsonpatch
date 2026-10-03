//
//  JSONPatchTests.swift
//  JSONPatchTests
//
//  Created by Michiel Horvers on 01/24/2020.
//  Copyright © 2020 Michiel Horvers.
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

fileprivate struct Person: Codable {
    var firstName: String
    var lastName: String
    var age: Int
}

struct JSONCodableTests {
    @Test func testIntegerSerializationBoundaries() throws {
        let literals = [
            "-9223372036854775808", "-9223372036854775807",
            "-9007199254740993", "-9007199254740992", "-9007199254740991",
            "-1", "0", "1",
            "9007199254740991", "9007199254740992", "9007199254740993",
            "9223372036854775806", "9223372036854775807", "9223372036854775808",
            "18446744073709551614", "18446744073709551615"
        ]
        for literal in literals {
            let data = Data("[{\"op\":\"add\",\"path\":\"/x\",\"value\":\(literal)}]".utf8)
            for patch in [try JSONPatch(data: data), try JSONDecoder().decode(JSONPatch.self, from: data)] {
                for serialized in [try patch.data(), try JSONEncoder().encode(patch)] {
                    // Typed decoding verifies exact integers; NSNumber equality can hide rounding.
                    if let expected = Int64(literal) {
                        let decoded = try JSONDecoder().decode([NumericOperation<Int64>].self, from: serialized)
                        #expect(decoded.first?.value == expected)
                    } else {
                        let decoded = try JSONDecoder().decode([NumericOperation<UInt64>].self, from: serialized)
                        #expect(decoded.first?.value == UInt64(literal))
                    }
                }
            }
        }
    }

    @Test func testBooleanAndFractionalSerialization() throws {
        for literal in ["true", "false", "-1.25", "0.5", "1.25"] {
            let data = Data("[{\"op\":\"add\",\"path\":\"/x\",\"value\":\(literal)}]".utf8)
            for patch in [try JSONPatch(data: data), try JSONDecoder().decode(JSONPatch.self, from: data)] {
                for serialized in [try patch.data(), try JSONEncoder().encode(patch)] {
                    if literal == "true" || literal == "false" {
                        let decoded = try JSONDecoder().decode([NumericOperation<Bool>].self, from: serialized)
                        #expect(decoded.first?.value == (literal == "true"))
                    } else {
                        let decoded = try JSONDecoder().decode([NumericOperation<Double>].self, from: serialized)
                        #expect(decoded.first?.value == Double(literal))
                    }
                }
            }
        }
    }

    @Test func testNSNumberEncodingPreservesNumericTypes() throws {
        let integers: [NSNumber] = [
            NSNumber(value: Int8(-2)), NSNumber(value: Int8(0)), NSNumber(value: Int8(1)),
            NSNumber(value: Int16.min), NSNumber(value: Int32.min), NSNumber(value: Int64.min),
            NSNumber(value: UInt8(0)), NSNumber(value: UInt8(1)), NSNumber(value: UInt8.max),
            NSNumber(value: UInt16.max), NSNumber(value: UInt32.max),
            NSNumber(value: Int64.max), NSNumber(value: UInt64.max)
        ]
        for number in integers {
            let data = try JSONEncoder().encode(JSONElement.number(value: number))
            if number == NSNumber(value: UInt64.max) {
                #expect(try JSONDecoder().decode(UInt64.self, from: data) == UInt64.max)
            } else {
                #expect(try JSONDecoder().decode(Int64.self, from: data) == number.int64Value)
            }
        }
        for number in [NSNumber(value: Float(1.25)), NSNumber(value: Double(-1.25))] {
            let data = try JSONEncoder().encode(JSONElement.number(value: number))
            #expect(try JSONDecoder().decode(Double.self, from: data) == number.doubleValue)
        }
        for value in [true, false] {
            let data = try JSONEncoder().encode(JSONElement.number(value: NSNumber(value: value)))
            #expect(try JSONDecoder().decode(Bool.self, from: data) == value)
        }
    }
    
    @Test func testCreatePatch() throws {
        let source = Person(firstName: "Michiel", lastName: "Horvers", age: 99)
        let target = Person(firstName: "Michiel", lastName: "Horvers", age: 100)
        
        let patch = try JSONPatch.createPatch(from: source, to: target)
        #expect(patch.operations.count == 1, "Patch should have only 1 operation, but has \(patch.operations.count)")
        
        guard patch.operations.count == 1 else { return }
        let dict = patch.operations[0].jsonObject
        
        #expect((dict["op"] as? String) == "replace", "Operation should be 'replace', but is: \(String(describing: dict["op"]))")
        #expect((dict["path"] as? String) == "/age", "Path should be 'age', but is: \(String(describing: dict["path"]))")
        #expect((dict["value"] as? Int) == 100, "Value should be 100, but is: \(String(describing: dict["value"]))")
    }
    
    @Test func testApplyPatch() throws {
        let person = Person(firstName: "Michiel", lastName: "Horvers", age: 99)
        let patchData = Data("""
        [
            { "op": "replace", "path": "/age", "value": 100 }
        ]
        """.utf8)
        let patch = try JSONDecoder().decode(JSONPatch.self, from: patchData)
        
        let patchedPerson = try patch.applied(to: person)
        #expect(patchedPerson.age == 100, "Age should be patched to 100, but is: \(patchedPerson.age)")
    }
}

fileprivate struct NumericOperation<Value: Decodable>: Decodable {
    let value: Value
}
