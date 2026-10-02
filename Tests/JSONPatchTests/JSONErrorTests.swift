import Foundation
import Testing
@testable import JSONPatch

struct JSONErrorTests {
    @Test(arguments: [
        "null", "true", "false", "1", "0", "-42", "9223372036854775807",
        "18446744073709551615", "1.25", "\"日本語👩‍💻\"",
        "[]", "{}", "{\"a\":[null,true,1,{\"b\":\"value\"}]}"
    ])
    func snapshotRoundTrip(_ json: String) throws {
        let original = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
        let snapshot = try JSONError.Value(jsonObject: original)
        #expect(try JSONElement(any: snapshot.jsonObject()) == JSONElement(any: original))
        let decoded = try JSONSerialization.jsonObject(with: snapshot.data, options: [.fragmentsAllowed])
        #expect(try JSONElement(any: decoded) == JSONElement(any: original))
    }

    @Test func booleanRemainsDistinctFromNumber() throws {
        let boolean = try JSONError.Value(jsonObject: true)
        let number = try JSONError.Value(jsonObject: 1)
        #expect(try JSONElement(any: boolean.jsonObject()) != JSONElement(any: number.jsonObject()))
    }

    @Test func failedTestCapturesIndependentSnapshots() throws {
        let expectedArray = NSMutableArray(array: [2])
        let foundArray = NSMutableArray(array: [1])
        let expected = NSMutableDictionary(dictionary: ["nested": expectedArray])
        let found = NSMutableDictionary(dictionary: ["nested": foundArray])
        let document = JSONElement.mutableObject(value: NSMutableDictionary(dictionary: ["value": found]))
        do {
            try document.test(value: JSONElement(any: expected), at: JSONPointer(string: "/value"))
            Issue.record("Expected a failed test")
        } catch JSONError.patchTestFailed(_, let expectedSnapshot, let foundSnapshot) {
            expectedArray.add(3)
            foundArray.add(4)
            expected["later"] = true
            found["later"] = false
            let actualSnapshot = try #require(foundSnapshot)
            #expect(try JSONElement(any: expectedSnapshot.jsonObject()) ==
                    JSONElement(any: ["nested": [2]]))
            #expect(try JSONElement(any: actualSnapshot.jsonObject()) ==
                    JSONElement(any: ["nested": [1]]))
        }
    }

    @Test func rejectsInvalidJSON() {
        for value: Any in [Date(), NSObject(), Double.infinity, Double.nan, ["date": Date()]] {
            #expect(throws: JSONError.invalidObjectType) {
                try JSONError.Value(jsonObject: value)
            }
        }
    }

    @Test func errorEqualityRemainsPathBased() throws {
        let one = try JSONError.Value(jsonObject: 1)
        let two = try JSONError.Value(jsonObject: 2)
        #expect(JSONError.patchTestFailed(path: "/a", expected: one, found: nil) ==
                JSONError.patchTestFailed(path: "/a", expected: two, found: one))
        #expect(JSONError.patchTestFailed(path: "/a", expected: one, found: nil) !=
                JSONError.patchTestFailed(path: "/b", expected: one, found: nil))
    }
}
