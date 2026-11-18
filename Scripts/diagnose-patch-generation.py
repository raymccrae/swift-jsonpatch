#!/usr/bin/env python3
"""Count stage 3 copy work in a temporary instrumented library, outside timing runs."""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

import patch_generation_benchmark as support


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError("Diagnostic instrumentation no longer matches the generator: " + before[:80])
    return source.replace(before, after)


def instrument(source):
    source = replace_once(source, "struct JSONPatchGenerator {", """struct JSONPatchGenerator {
    nonisolated(unsafe) private static var diagnostic: [String: Any] = [:]
    nonisolated(unsafe) private static var diagnosticEquality = 0
    nonisolated(unsafe) private static var diagnosticMatches = 0
    private static func diagnosticKind(_ value: JSONElement) -> String {
        switch value {
        case .null: return "null"
        case .number(let n): return n.isBoolean ? "boolean" : "number"
        case .string: return "string"
        case .array, .mutableArray: return "array"
        case .object, .mutableObject: return "object"
        }
    }
""")
    source = replace_once(source, "        switch (lhs, rhs) {", "        diagnosticEquality += 1\n        switch (lhs, rhs) {")
    source = replace_once(source, "        var generator = JSONPatchGenerator()", """        var generator = JSONPatchGenerator()
        diagnostic = [:]; diagnosticEquality = 0; diagnosticMatches = 0
        defer {
            diagnostic["recursive_equality_calls"] = diagnosticEquality
            diagnostic["successful_searches"] = diagnosticMatches
            diagnostic["number_cost_cache_entries"] = generator.numberSizes.count
            var counts: [String: Int] = [:]
            for op in generator.operations {
                let name: String
                switch op {
                case .add: name = "add"
                case .remove: name = "remove"
                case .replace: name = "replace"
                case .copy: name = "copy"
                case .move: name = "move"
                case .test: name = "test"
                }
                counts[name, default: 0] += 1
            }
            diagnostic["operation_counts"] = counts
            if let bytes = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]) {
                FileHandle.standardError.write(bytes + Data([10]))
            }
        }""")
    source = replace_once(source, "    private mutating func resolveCopies() {", """    private mutating func resolveCopies() {
        Self.diagnostic["collected_sources"] = unchanged.count
        var sourceKinds: [String: Int] = [:]
        var additionKinds: [String: Int] = [:]
        var sourceSizes: [Int] = []
        var additionSizes: [Int] = []
        for source in unchanged {
            sourceKinds[Self.diagnosticKind(source.value), default: 0] += 1
            if let bytes = CopyCost.literalSize(source.value, limit: Int.max - 1) { sourceSizes.append(bytes) }
        }
        for op in operations {
            if case .add(_, let value) = op {
                additionKinds[Self.diagnosticKind(value), default: 0] += 1
                if let bytes = CopyCost.literalSize(value, limit: Int.max - 1) { additionSizes.append(bytes) }
            }
        }
        Self.diagnostic["source_kinds"] = sourceKinds
        Self.diagnostic["addition_kinds"] = additionKinds
        Self.diagnostic["planned_additions"] = additionKinds.values.reduce(0, +)
        Self.diagnostic["source_value_bytes_min_max"] = [sourceSizes.min() ?? 0, sourceSizes.max() ?? 0]
        Self.diagnostic["addition_value_bytes_min_max"] = [additionSizes.min() ?? 0, additionSizes.max() ?? 0]
""")
    source = replace_once(source, "        guard !queries.isEmpty else { return }",
                          '        Self.diagnostic["eligible_queries"] = queries.count\n        guard !queries.isEmpty else { return }')
    source = replace_once(source, "            if source.encodedBytes != shortestSourceBytes {",
                          "            Self.diagnosticMatches += 1\n            if source.encodedBytes != shortestSourceBytes {")
    source = replace_once(source, "            operations[index] = .copy(from: source.path, path: path)\n        }",
                          '            operations[index] = .copy(from: source.path, path: path)\n        }\n        Self.diagnostic["built_index"] = lookup.builtIndex\n        Self.diagnostic["linear_comparisons"] = lookup.linearComparisons')
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", action="append", default=[], help="Case substring or glob; repeat for a union")
    parser.add_argument("--output", type=pathlib.Path, default=support.ROOT / "Benchmarks/Results/stage3-diagnostics.json")
    args = parser.parse_args()
    cases = [c for c in support.corpus("full") if c["family"] in ("copies", "encoding")]
    if args.case:
        cases = [c for c in cases if any(p in c["id"] or fnmatch.fnmatchcase(c["id"], p) for p in args.case)]
    if not cases:
        parser.error("No diagnostic cases selected")
    original = support.ROOT / "Sources/JSONPatch/JSONPatchGenerator.swift"
    result = {"diagnostic_schema_version": 1, "generator_sha256": support.digest(original.read_bytes()),
              "instrumentation_sha256": support.digest(pathlib.Path(__file__).read_bytes()),
              "harness_sha256": support.harness_hash(), "library": support.revision(support.ROOT),
              "note": "Untimed instrumented snapshot. Sources are collected after the cheap-literal policy; equality counts include recursive checks.",
              "compiler_flags": ["-O", "-swift-version", "6", "-warnings-as-errors"], "results": []}
    with tempfile.TemporaryDirectory(prefix="jsonpatch-diagnostic-") as directory:
        temporary = pathlib.Path(directory)
        shutil.copytree(support.ROOT / "Sources", temporary / "Sources")
        copied = temporary / "Sources/JSONPatch/JSONPatchGenerator.swift"
        copied.write_text(instrument(copied.read_text()))
        main_file = temporary / "main.swift"
        main_file.write_text('''import Foundation
let arguments = CommandLine.arguments
let source = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
let target = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
let patch = try JSONPatch(source: source, target: target, options: [.fragmentsAllowed])
_ = try patch.data()
''')
        binary = temporary / "diagnostic"
        env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(temporary / "clang-cache"))
        subprocess.run(["swiftc", "-O", "-swift-version", "6", "-warnings-as-errors",
                        "-module-cache-path", str(temporary / "module-cache"), "-o", str(binary)] +
                       [str(p) for p in sorted((temporary / "Sources").rglob("*.swift"))] + [str(main_file)],
                       env=env, check=True, timeout=180)
        for case in cases:
            source, target = temporary / "source.json", temporary / "target.json"
            source.write_bytes(case["source"])
            target.write_bytes(case["target"])
            process = subprocess.run([str(binary), str(source), str(target)], check=True,
                                     text=True, capture_output=True, timeout=180)
            stats = json.loads(process.stderr)
            queries = stats.get("eligible_queries", 0)
            stats["search_hit_rate"] = stats.get("successful_searches", 0) / queries if queries else None
            result["results"].append({"case": support.case_metadata(case), "counters": stats})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    support.write_json(args.output, result)


if __name__ == "__main__":
    main()
