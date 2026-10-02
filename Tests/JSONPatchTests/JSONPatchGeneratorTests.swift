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

import Foundation
import Testing
@testable import JSONPatch

struct JSONPatchGeneratorTests {

    var sourceData: Data { get throws { try TestResources.data("bigexample1") } }
    var targetData: Data { get throws { try TestResources.data("bigexample2") } }

    @Test func testBigPatch() throws {
        var source = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let target = try JSONSerialization.jsonElement(with: targetData, options: [])
        let patch = try JSONPatch(source: source, target: target)

        try source.apply(patch: patch)

        #expect(!patch.operations.isEmpty)
        #expect(source == target)
    }

    @Test func testPerformanceGenerate() throws {
        let source = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let target = try JSONSerialization.jsonElement(with: targetData, options: [])

        // Note: Swift Testing doesn't have a direct equivalent to measure(),
        // but we can still run the code to ensure it works
        _ = try JSONPatch(source: source, target: target)
    }

    @Test func testNoDifferences() throws {
        let source = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let patch = try JSONPatch(source: source, target: source)
        #expect(patch.operations.count == 0)
    }

}
