//
//  JSONPatchGeneratorTests.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 02/12/2018.
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

class JSONPatchGeneratorTests: XCTestCase {

    static let sourceURL = Bundle.test.url(forResource: "bigexample1", withExtension: "json")!
    static let targetURL = Bundle.test.url(forResource: "bigexample2", withExtension: "json")!

    var sourceData: Data { return try! Data(contentsOf: JSONPatchGeneratorTests.sourceURL) }
    var targetData: Data { return try! Data(contentsOf: JSONPatchGeneratorTests.targetURL) }

    func testBigPatch() throws {
        var source = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let target = try JSONSerialization.jsonElement(with: targetData, options: [])
        let patch = try JSONPatch(source: source, target: target)

        try source.apply(patch: patch)

        XCTAssertFalse(patch.operations.isEmpty)
        XCTAssertEqual(source, target)
    }

    func testPerformanceGenerate() throws {
        let source = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let target = try JSONSerialization.jsonElement(with: targetData, options: [])

        self.measure {
            do {
                _ = try JSONPatch(source: source, target: target)
            } catch {
                XCTFail("Error: \(error)")
            }
        }
    }

    func testNoDifferences() throws {
        let source = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let patch = try JSONPatch(source: source, target: source)
        XCTAssertEqual(patch.operations.count, 0)
    }

}
