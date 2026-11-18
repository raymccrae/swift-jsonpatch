#!/usr/bin/env python3
"""Build once, validate fixtures, and measure public JSONPatch APIs in fresh processes."""
from __future__ import annotations

import argparse
import contextlib
import datetime
import fnmatch
import io
import json
import pathlib
import subprocess
import sys
import tarfile
import tempfile

import patch_generation_benchmark as support


def library_snapshot(stack, path, ref):
    if not ref:
        return path, support.revision(path)
    commit = support.command_output(["git", "rev-parse", ref + "^{commit}"], path)
    if not commit:
        raise ValueError("Cannot resolve library revision: " + ref)
    archive = subprocess.run(["git", "archive", "--format=tar", commit], cwd=path,
                             check=True, capture_output=True).stdout
    directory = pathlib.Path(stack.enter_context(tempfile.TemporaryDirectory(prefix="jsonpatch-library-")))
    with tarfile.open(fileobj=io.BytesIO(archive)) as contents:
        for member in contents.getmembers():
            name = pathlib.PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts or member.issym() or member.islnk():
                raise ValueError("Unsafe archive member: " + member.name)
        contents.extractall(directory)
    return directory, {"commit": commit, "dirty": False, "ref": ref,
                       "source_tree": support.command_output(["git", "rev-parse", commit + ":Sources"], path),
                       "source_diff_sha256": support.digest(b"")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("quick", "full"), default="quick")
    parser.add_argument("--case", action="append", default=[], help="Case ID glob or substring; repeat to select a union")
    parser.add_argument("--mode", choices=("all",) + support.MODES, default="all")
    parser.add_argument("--processes", type=int, default=3, help="Independent processes (pairs when comparing)")
    parser.add_argument("--samples", type=int, default=10)
    parser.add_argument("--sample-ms", type=float, default=20)
    parser.add_argument("--warmup", type=int, default=3)
    parser.add_argument("--max-iterations", type=int, default=10000)
    parser.add_argument("--timeout-seconds", type=float, default=60)
    parser.add_argument("--memory-limit-mb", type=int, default=1024)
    parser.add_argument("--library-path", type=pathlib.Path, default=support.ROOT)
    parser.add_argument("--library-ref", help="Export this immutable Git revision as the measured library")
    parser.add_argument("--baseline-library-path", type=pathlib.Path)
    parser.add_argument("--baseline-ref", help="Run alternating baseline/candidate process pairs")
    parser.add_argument("--validate-only", action="store_true", help="Validate every selected case in all four mutability combinations")
    parser.add_argument("--output", type=pathlib.Path, default=support.ROOT / "Benchmarks/Results/latest")
    args = parser.parse_args()
    for name in ("processes", "samples", "sample_ms", "max_iterations", "timeout_seconds", "memory_limit_mb"):
        if not 0 < getattr(args, name) < 1000001:
            parser.error("Invalid --" + name.replace("_", "-"))
    if not 0 <= args.warmup <= 1000000:
        parser.error("Invalid --warmup")
    cases = support.corpus(args.profile)
    if args.case:
        cases = [case for case in cases if any(pattern in case["id"] or fnmatch.fnmatchcase(case["id"], pattern) for pattern in args.case)]
    if not cases:
        parser.error("No cases selected")
    modes = support.MODES if args.mode == "all" else (args.mode,)
    if args.validate_only:
        modes = ("generate",)
        expanded = []
        for case in cases:
            for source_mutable, target_mutable in ((False, False), (True, False), (False, True), (True, True)):
                item = dict(case)
                item["flags"] = [flag for flag in case["flags"] if flag not in ("source-mutable", "target-mutable")]
                if source_mutable:
                    item["flags"].append("source-mutable")
                if target_mutable:
                    item["flags"].append("target-mutable")
                item["id"] += f"/mutable-{int(source_mutable)}{int(target_mutable)}"
                expanded.append(item)
        cases = expanded
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    settings = {key: getattr(args, key) for key in ("samples", "sample_ms", "warmup", "max_iterations", "timeout_seconds", "memory_limit_mb", "processes", "profile", "validate_only")}
    environment = support.environment()
    harness = {"version": 1, "sha256": support.harness_hash(), "revision": support.revision(support.ROOT),
               "corpus_version": support.CORPUS_VERSION, "seed": support.SEED}
    failed = False
    with contextlib.ExitStack() as stack:
        requested = []
        if args.baseline_ref or args.baseline_library_path:
            requested.append(("baseline", args.baseline_library_path or args.library_path, args.baseline_ref))
            requested.append(("candidate", args.library_path, args.library_ref))
        else:
            requested.append(("run", args.library_path, args.library_ref))
        variants = []
        for label, path, ref in requested:
            source, metadata = library_snapshot(stack, path.resolve(), ref)
            content = sorted((source / "Sources").rglob("*.swift")) + [source / "Package.swift"]
            metadata["content_sha256"] = support.digest(b"".join(str(p.relative_to(source)).encode() + b"\0" + p.read_bytes() for p in content))
            binary = support.build(source, output / ("build-" + label))
            run = {"schema_version": support.SCHEMA, "label": label,
                   "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   "harness": harness, "library": metadata, "environment": environment,
                   "settings": settings, "results": []}
            variants.append((binary, run))
        for case_index, case in enumerate(cases):
            print(f"[{case_index + 1}/{len(cases)}] {case['id']}", file=sys.stderr, flush=True)
            for mode in modes:
                entries = []
                for _, run in variants:
                    item = {"case": support.case_metadata(case), "mode": mode, "processes": []}
                    run["results"].append(item)
                    entries.append(item)
                for pair in range(1 if args.validate_only else args.processes):
                    order = list(range(len(variants)))
                    if pair % 2:
                        order.reverse()
                    for index in order:
                        binary, run = variants[index]
                        with tempfile.TemporaryDirectory(prefix="jsonpatch-case-") as temporary:
                            directory = pathlib.Path(temporary)
                            result = support.run_worker(binary, case, mode, settings, directory,
                                                        validate_only=args.validate_only)
                            result["pair"] = pair
                            if result["status"] == "passed" and not args.validate_only:
                                memory = support.run_worker(binary, case, mode, settings, directory, memory_only=True)
                                result["memory_measurement"] = memory
                                if memory["status"] != "passed":
                                    result["status"] = memory["status"]
                                else:
                                    result["measurement_peak_rss_bytes"] = memory["peak_rss_bytes"]
                            failed |= result["status"] != "passed"
                            if result["status"] != "passed":
                                print(f"  {run['label']} {mode}: {result['status']} {result.get('error', '')}", file=sys.stderr)
                            entries[index]["processes"].append(result)
                for index, (_, run) in enumerate(variants):
                    entries[index]["summary"] = support.summarize(entries[index]["processes"])
                    support.write_json(output / (run["label"] + ".json"), run)
                    (output / (run["label"] + ".md")).write_text(support.report_run(run))
        if len(variants) == 2:
            subprocess.run([sys.executable, str(support.ROOT / "Scripts/compare-patch-generation.py"),
                            str(output / "baseline.json"), str(output / "candidate.json"),
                            "--output", str(output / "comparison.md")], check=True)
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Benchmark harness failed: {error}", file=sys.stderr)
        sys.exit(1)
