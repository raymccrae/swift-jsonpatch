#!/usr/bin/env python3
"""Export a local experimental library for paired benchmarks; never edit the checkout."""
from __future__ import annotations

import argparse
import io
import pathlib
import re
import shutil
import subprocess
import tarfile

import patch_generation_benchmark as support


ROOT_SIZE = '''        // Experimental whole-document selection, after copy resolution.
        // Limit operation wrappers and encoded-byte estimation separately.
        if generator.operations.count >= 2 && generator.operations.count <= 2_048 {
            let detailed = JSONPatch(operations: generator.operations)
            if let old = CopyCost.literalSize(.array(value: detailed.jsonArray), limit: 65_536), old <= 65_536 {
                let replacement = JSONPatch(operations: [.replace(path: .wholeDocument, value: target)])
                if let new = CopyCost.literalSize(.array(value: replacement.jsonArray), limit: old - 1), new < old {
                    return replacement.operations
                }
            }
        }
'''

ROOT_SIZE_DIRECT = '''        // Experimental operation-specific cost estimates, without JSON wrappers.
        func operationSize(_ operation: JSONPatch.Operation, limit: Int) -> Int? {
            let path: JSONPointer
            let from: JSONPointer?
            let value: JSONElement?
            var bytes: Int
            switch operation {
            case .replace(let p, let v): path = p; value = v; from = nil; bytes = 33
            case .add(let p, let v): path = p; value = v; from = nil; bytes = 29
            case .remove(let p): path = p; value = nil; from = nil; bytes = 23
            case .copy(let f, let p), .move(let f, let p): path = p; from = f; value = nil; bytes = 29
            case .test(let p, let v): path = p; value = v; from = nil; bytes = 30
            }
            guard bytes <= limit else { return nil }
            bytes += CopyCost.stringSize(path.string, limit: limit - bytes)
            guard bytes <= limit else { return nil }
            if let from {
                bytes += CopyCost.stringSize(from.string, limit: limit - bytes)
                guard bytes <= limit else { return nil }
            }
            if let value {
                guard let size = CopyCost.literalSize(value, limit: limit - bytes) else { return nil }
                bytes += size
            }
            return bytes <= limit ? bytes : nil
        }
        if generator.operations.count >= 2 && generator.operations.count <= 2_048 {
            var old = 1 // [] plus one comma per operation, with no trailing comma
            var measured = true
            for operation in generator.operations {
                guard old < 65_536, let size = operationSize(operation, limit: 65_535 - old) else {
                    measured = false; break
                }
                old += size + 1
            }
            // A singleton root replacement costs 37 bytes before its value.
            if measured && old > 37,
               let size = CopyCost.literalSize(target, limit: old - 38), size <= old - 38 {
                return [.replace(path: .wholeDocument, value: target)]
            }
        }
'''


# Historical structural prototype, reproducible from the stage 4 sources.
COMPLETE_REPLACEMENT = '''    // A complete set of direct replacements contains every target value once,
    // just as a container replacement does. Values cancel from the size choice:
    // only JSON syntax, operation metadata, and repeated paths differ. There are
    // no unchanged descendants to lose as copy sources and no additions whose
    // literals could become smaller copies. Keep small and partial edits granular.
    static let minimumReplacementChildren = 2

    private static func adapt(_ comparison: Comparison, target: JSONElement) -> Comparison {
        switch comparison {
        case .object(let removals, let additions, let children):
            if removals.isEmpty && additions.isEmpty && children.count >= minimumReplacementChildren &&
                children.allSatisfy({ $0.1.isReplacement }) {
                return .replace(target)
            }
        case .array(let array):
            if array.parts.count >= minimumReplacementChildren && array.parts.allSatisfy({ part in
                if case .change(let source, let target, let child) = part {
                    return source == target && child.isReplacement
                }
                return false
            }) {
                return .replace(target)
            }
        default: break
        }
        return comparison
    }

'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strategy", required=True, choices=("root-size", "root-size-direct", "complete-small", "complete-32", "prefer-smaller"))
    parser.add_argument("--base-ref", help="Export this local Git revision; otherwise copy the working library")
    parser.add_argument("--output", type=pathlib.Path, required=True, help="New directory for the experimental library")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; choose a new directory")
    args.output.mkdir(parents=True)
    if args.base_ref:
        archive = subprocess.run(["git", "archive", args.base_ref, "Sources", "Package.swift"],
                                 cwd=support.ROOT, capture_output=True, check=True).stdout
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:
            for member in source.getmembers():
                path = pathlib.PurePosixPath(member.name)
                if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                    raise ValueError("Unexpected archive entry: " + member.name)
                destination = args.output / path
                if member.isdir():
                    destination.mkdir(parents=True, exist_ok=True)
                else:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(source.extractfile(member).read())
    else:
        shutil.copytree(support.ROOT / "Sources", args.output / "Sources")
        shutil.copy2(support.ROOT / "Package.swift", args.output / "Package.swift")
    generator = args.output / "Sources/JSONPatch/JSONPatchGenerator.swift"
    text = generator.read_text()
    original_hash = support.digest(generator.read_bytes())
    if args.strategy in ("root-size", "root-size-direct"):
        marker = "        generator.resolveCopies()\n"
        if text.count(marker) != 1:
            raise ValueError("Root-size insertion marker no longer matches")
        text = text.replace(marker, marker + (ROOT_SIZE if args.strategy == "root-size" else ROOT_SIZE_DIRECT))
    elif args.strategy == "prefer-smaller":
        marker = "        self.init(operations: try JSONPatchGenerator.generatePatch(source: source, target: target))"
        if text.count(marker) != 1 or "generationOptions: [GenerationOption]" not in text:
            raise ValueError("Prefer-smaller requires the stage 5 public generation option")
        text = text.replace(marker, "        try self.init(source: source, target: target, generationOptions: [.preferSmallerPatch])")
    else:
        if "static let minimumReplacementChildren" not in text:
            unchanged = """        var isUnchanged: Bool {
            if case .unchanged = self { return true }
            return false
        }
"""
            replacement = unchanged + """
        var isReplacement: Bool {
            if case .replace = self { return true }
            return false
        }
"""
            markers = [(unchanged, replacement),
                       ("    // Compare each corresponding pair once.", COMPLETE_REPLACEMENT + "    // Compare each corresponding pair once."),
                       ("return try compareObjects(a, b, source: source, matchArrays: matchArrays)",
                        "return try Self.adapt(compareObjects(a, b, source: source, matchArrays: matchArrays), target: target)"),
                       ("return try compareArrays(a, b, source: source, matchArrays: matchArrays)",
                        "return try Self.adapt(compareArrays(a, b, source: source, matchArrays: matchArrays), target: target)")]
            for before, after in markers:
                if text.count(before) != 1:
                    raise ValueError("Historical adaptive prototype marker no longer matches")
                text = text.replace(before, after)
        pattern = r"static let minimumReplacementChildren = (?:2|32)\b"
        if len(re.findall(pattern, text)) != 1:
            raise ValueError("Threshold experiments require the stage 5 adaptive implementation")
        minimum = 2 if args.strategy == "complete-small" else 32
        text = re.sub(pattern, "static let minimumReplacementChildren = " + str(minimum), text)
    generator.write_text(text)
    support.write_json(args.output / "experiment.json", {
        "strategy": args.strategy, "base_ref": args.base_ref, "working_revision": support.revision(support.ROOT),
        "original_generator_sha256": original_hash, "experimental_generator_sha256": support.digest(generator.read_bytes()),
        "script_sha256": support.digest(pathlib.Path(__file__).read_bytes()),
        "note": "Temporary benchmark library. prefer-smaller redirects existing initializer calls to the public option; other strategies are experiments.",
    })
    print(args.output.resolve())


if __name__ == "__main__":
    main()
