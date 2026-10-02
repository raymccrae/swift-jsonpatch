import Foundation
import Testing
@testable import JSONPatch

private actor PatchWorker {
    func apply(document: Data, patch: Data, options: [JSONPatch.ApplyOption]) throws -> Data {
        try JSONPatch(data: patch).apply(to: document, applyingOptions: options)
    }

    func pointerString(_ pointer: JSONPointer) -> String { pointer.string }
}

struct ConcurrencyTests {
    @Test func patchingAcrossActorBoundary() async throws {
        let worker = PatchWorker()
        let pointer = try JSONPointer(string: "/nested")
        #expect(await worker.pointerString(pointer) == "/nested")
        let result = try await worker.apply(
            document: Data(#"{"nested":{"value":1}}"#.utf8),
            patch: Data(#"[{"op":"replace","path":"/value","value":2}]"#.utf8),
            options: [.applyOnCopy, .relative(to: pointer)])
        #expect(try JSONSerialization.jsonElement(with: result, options: []) ==
                JSONElement(any: ["nested": ["value": 2]]))
    }

    @Test func failedTestErrorCrossesActorBoundary() async throws {
        let worker = PatchWorker()
        do {
            _ = try await worker.apply(
                document: Data(#"{"value":null}"#.utf8),
                patch: Data(#"[{"op":"test","path":"/value","value":true}]"#.utf8),
                options: [])
            Issue.record("Expected a failed test")
        } catch JSONError.patchTestFailed(let path, let expected, let found) {
            #expect(path == "/value")
            #expect(try JSONElement(any: expected.jsonObject()) == JSONElement(true))
            #expect(try #require(found).jsonObject() is NSNull)
        }
    }

    @Test func errorAndOptionsCrossTaskBoundary() async throws {
        let snapshot = try JSONError.Value(jsonObject: ["a": [1, 2]])
        let error = JSONError.patchTestFailed(path: "/a", expected: snapshot, found: nil)
        let options: [JSONPatch.ApplyOption] = [.ignoreNonexistentValues]
        let result = await Task.detached { (error, options) }.value
        #expect(result.0 == error)
        #expect(result.1 == options)
        if case .patchTestFailed(_, let expected, let found) = result.0 {
            #expect(expected.data == snapshot.data)
            #expect(found == nil)
        }
    }
}
