//
//  JSONFileTestCase.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 21/11/2018.
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

import UIKit
import XCTest
@testable import JSONPatch

class JSONFileTestCase: XCTestCase {

    let index: Int
    let testJson: [String: Any]

    class var filename: String? {
        return nil
    }

    override class var defaultTestSuite: XCTestSuite {
        let suite = XCTestSuite(forTestCaseClass: self)
        guard let filename = self.filename else {
            return suite
        }

        do {
            let tests = try loadJSONTestFile(filename)
            for (index, test) in tests.enumerated() {
                if let disabled = test["disabled"] as? NSNumber, disabled.boolValue {
                    continue
                }
                suite.addTest(JSONFileTestCase(test, index: index))
            }
        } catch {
            XCTFail()
        }

        return suite
    }

    override var testRunClass: AnyClass? {
        return XCTestCaseRun.self
    }

    override var name: String {
        return "test_\(index)"
    }

    init(_ testJson: [String: Any], index: Int) {
        self.testJson = testJson
        self.index = index
        super.init(invocation: nil)
    }

    override func perform(_ run: XCTestRun) {
        run.start()
        let comment = testJson["comment"] ?? name
        print("Started: \(comment)")
        performJsonTest()
        print("Finished: \(comment)")
        run.stop()
    }

    func performJsonTest() {
        guard let doc = testJson["doc"] else {
            XCTFail("doc not found")
            return
        }

        guard let patch = testJson["patch"] as? NSArray else {
            XCTFail("patch not found")
            return
        }

        let comment = testJson["comment"] ?? name

        do {
            let jsonPatch = try JSONPatch(jsonArray: patch)
            let result = try jsonPatch.apply(to: doc)

            if let expected = testJson["expected"] {
                guard (result as? NSObject)?.isEqual(expected) ?? false else {
                    XCTFail("result does not match expected: \(comment)")
                    return
                }
            } else {
                XCTFail("Error should occur: \(comment)")
            }
        } catch {
            guard let _ = testJson["error"] as? String else {
                XCTFail("Unexpected error: \(comment)")
                return
            }
        }
    }

}

extension JSONFileTestCase {

    private class func loadJSONTestFile(_ filename: String) throws -> [[String: Any]] {
        guard let url = Bundle.test.url(forResource: filename,
                                        withExtension: "json") else {
            return []
        }
        let data = try Data(contentsOf: url)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let jsonArray = jsonObject as? [[String: Any]] else {
            return []
        }
        return jsonArray
    }

}
