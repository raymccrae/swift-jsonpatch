//
//  JSONFileTests.swift
//  JSONPatchTests
//
//  Created by Assistant on 2024.
//  Copyright © 2024.
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

struct JSONFileTests {

    private class BundleToken {}

    private static func loadJSONTestFile(_ filename: String) throws -> [[String: Any]] {
        let bundle = Bundle(for: BundleToken.self)
        let url: URL
        if let bundleURL = bundle.url(forResource: filename, withExtension: "json") {
            url = bundleURL
        } else {
            // Fallback to source directory
            let cwd = FileManager.default.currentDirectoryPath
            let sourceDir = URL(fileURLWithPath: cwd).appendingPathComponent("Tests").appendingPathComponent("JSONPatchTests")
            url = sourceDir.appendingPathComponent(filename).appendingPathExtension("json")
        }
        let data = try Data(contentsOf: url)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let jsonArray = jsonObject as? [[String: Any]] else {
            throw NSError(domain: "JSONFileTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure in \(filename).json"])
        }
        return jsonArray
    }

    @Test(arguments: ["tests", "spec_tests", "extra"])
    func testJSONFile(filename: String) throws {
        let tests = try Self.loadJSONTestFile(filename)

        for (index, testJson) in tests.enumerated() {
            if let disabled = testJson["disabled"] as? NSNumber, disabled.boolValue {
                continue
            }

            let comment = testJson["comment"] as? String ?? "test_\(index)"

            guard let doc = testJson["doc"] else {
                Issue.record("doc not found in test: \(comment)")
                continue
            }

            guard let patch = testJson["patch"] as? NSArray else {
                Issue.record("patch not found in test: \(comment)")
                continue
            }

            do {
                let jsonPatch = try JSONPatch(jsonArray: patch)
                let result = try jsonPatch.apply(to: doc)

                if let expected = testJson["expected"] {
                    guard (result as? NSObject)?.isEqual(expected) ?? false else {
                        Issue.record("result does not match expected in test: \(comment)")
                        continue
                    }
                } else {
                    Issue.record("Error should occur in test: \(comment)")
                }
            } catch {
                guard let _ = testJson["error"] as? String else {
                    Issue.record("Unexpected error in test \(comment): \(error)")
                    continue
                }
            }
        }
    }
}