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

    @Test func testGenerateLargeFixtureSmoke() throws {
        let source = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let target = try JSONSerialization.jsonElement(with: targetData, options: [])

        // Timings are measured by the standalone Benchmarks package.
        _ = try JSONPatch(source: source, target: target)
    }

    @Test func testNoDifferences() throws {
        let source = try JSONSerialization.jsonElement(with: sourceData, options: [.mutableContainers])
        let patch = try JSONPatch(source: source, target: source)
        #expect(patch.operations.count == 0)
    }

    @Test(arguments: [
        ("[[1,2,3],[]]", "[[1],[2,3]]"),
        ("[[1,2,3,4],[]]", "[[1],[4,2,3]]"),
        ("[[1,2,2,3],[]]", "[[1],[2,3,2]]"),
        ("[[1,2,3],[],[]]", "[[1],[2],[3]]"),
        ("[[],[1,2,3]]", "[[2,3],[1]]"),
        ("[[1,2,3],[4,5,6],[]]", "[[1],[4],[2,6,3,5]]"),
        ("[[[1],[2],[3]],[]]", "[[[1]],[[2],[3]]]"),
        ("[[[1,2,3],[]],[]]", "[[[1],[2,3]],[]]"),
        ("[[1,2,3],[]]", "[[9],[2,3]]"),
        ("[[1,2,3],[]]", "[[1],[1,2,3]]"),
        (#"{"source":[1,2,3],"target":[]}"#, #"{"source":[1],"target":[2,3]}"#)
    ])
    func testArrayTransferRoundTrip(sourceJSON: String, targetJSON: String) throws {
        let target = try JSONSerialization.jsonElement(with: Data(targetJSON.utf8), options: [])
        for options: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
            var source = try JSONSerialization.jsonElement(with: Data(sourceJSON.utf8), options: options)
            let patch = try JSONPatch(source: source, target: target)

            try source.apply(patch: patch)

            #expect(source == target)
        }
    }

    @Test(arguments: [
        (#"{"\u00e9":1,"e\u0301":2}"#, #"{"\u00e9":3,"e\u0301":4}"#),
        (#"{"\u00e9":1}"#, #"{"e\u0301":1}"#),
        (#"{"e\u0301":1}"#, #"{"\u00e9":1}"#),
        (#"{"\u00e9":1}"#, #"{"\u00e9":1,"e\u0301":2}"#),
        (#"{"e\u0301":2}"#, #"{"\u00e9":1,"e\u0301":2}"#),
        (#"{"\u00e9":1,"e\u0301":2}"#, #"{"\u00e9":1}"#),
        (#"{"\u00e9":1,"e\u0301":2}"#, #"{"e\u0301":2}"#),
        (#"{"\u00e9":1,"e\u0301":2}"#, #"{}"#),
        (#"{}"#, #"{"\u00e9":1,"e\u0301":2}"#)
    ])
    func testUnicodeKeyRoundTrip(sourceJSON: String, targetJSON: String) throws {
        // Exercise equality short circuits at the root and inside objects/arrays.
        for (prefix, suffix) in [("", ""), (#"{"nested":"#, "}"), (#"{"nested":["#, "]}")] {
            try assertExactRoundTrip(sourceJSON: prefix + sourceJSON + suffix,
                                     targetJSON: prefix + targetJSON + suffix)
        }
    }

    @Test func testUnchangedUnicodeKeys() throws {
        let data = Data(#"{"\u00e9":1,"e\u0301":2,"nested":[{"e\u0301":3}]}"#.utf8)
        let source = try JSONSerialization.jsonElement(with: data, options: [])
        let target = try JSONSerialization.jsonElement(with: data, options: [.mutableContainers])
        let patch = try JSONPatch(source: source, target: target)
        #expect(patch.operations.isEmpty)
        #expect(try GenerationJSON(source.rawValue) == GenerationJSON(target.rawValue))
    }

    @Test func testUnicodeKeysInCopyCandidates() throws {
        try assertExactRoundTrip(sourceJSON: #"{"stable":{"\u00e9":1}}"#,
                                 targetJSON: #"{"stable":{"\u00e9":1},"added":{"e\u0301":1}}"#)
        try assertExactRoundTrip(sourceJSON: #"[{"\u00e9":1}]"#,
                                 targetJSON: #"[{"\u00e9":1},{"e\u0301":1}]"#)
        try assertExactRoundTrip(sourceJSON: #"{"stable":[{"\u00e9":1}]}"#,
                                 targetJSON: #"{"stable":[{"\u00e9":1}],"added":[{"e\u0301":1}]}"#)
    }

    private func assertExactRoundTrip(sourceJSON: String, targetJSON: String) throws {
        try assertGeneratedPatch(source: sourceJSON, target: targetJSON)
    }

}
