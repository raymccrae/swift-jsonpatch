import Foundation
import Testing
@testable import PatchGenerationBenchmarks

struct ExactJSONTests {
    func value(_ json: String) throws -> ExactJSON { try ExactJSON(readJSON(Data(json.utf8))) }

    @Test func objectOrderDoesNotMatter() throws {
        #expect(try value(#"{"a":1,"b":[true,null]}"#) == value(#"{"b":[true,null],"a":1.0}"#))
    }

    @Test func distinctUnicodeKeysAndStringsRemainDistinct() throws {
        #expect(try value(#"{"\u00e9":1}"#) != value(#"{"e\u0301":1}"#))
        #expect(try value(#""\u00e9""#) != value(#""e\u0301""#))
        let object = try value(#"{"\u00e9":1,"e\u0301":2}"#)
        guard case .object(let entries) = object else { Issue.record("Expected object"); return }
        #expect(entries.count == 2)
        #expect(try object != value(#"{"\u00e9":2,"e\u0301":1}"#))
    }

    @Test func booleansAreNotNumbers() throws {
        #expect(try value("true") != value("1"))
        #expect(try value("false") != value("0"))
        #expect(try value("[true]") != value("[1]"))
    }

    @Test func preservesIntegerPrecision() throws {
        #expect(try value("9007199254740992") != value("9007199254740993"))
        #expect(try value("18446744073709551615") != value("18446744073709551614"))
        #expect(try value("-9223372036854775808") != value("-9223372036854775807"))
        #expect(try value("1") == value("1.0"))
    }

    @Test func detectsMissingNullAndArrayOrder() throws {
        #expect(try value(#"{"":null}"#) != value("{}"))
        #expect(try value("[1,2]") != value("[2,1]"))
        #expect(try value("null") != value("false"))
    }

    @Test func mutableAndImmutableParsingAgree() throws {
        let bytes = Data(#"{"\u00e9":[{"e\u0301":9007199254740993}],"":true}"#.utf8)
        #expect(try ExactJSON(readJSON(bytes)) == ExactJSON(readJSON(bytes, mutable: true)))
    }

    @Test func inputRestorationAndPatchReuse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.json")
        let target = directory.appendingPathComponent("target.json")
        try Data("[[1,2,3],[]]".utf8).write(to: source)
        try Data("[[1],[2,3]]".utf8).write(to: target)
        for mode in Measurement.allCases {
            var options = WorkerOptions(source: source.path, target: target.path, mode: mode)
            options.samples = 2
            options.sampleMS = 0.01
            options.maxIterations = 4
            options.sourceMutable = true
            let result = try Worker(options).run()
            #expect(result["validation"] as? String == "passed")
            #expect((result["samples_ns"] as? [Double])?.count == 2)
        }
    }
}
