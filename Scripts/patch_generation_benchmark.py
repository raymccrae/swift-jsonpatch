"""Shared corpus, process control, and report support for patch benchmarks (stdlib only)."""
from __future__ import annotations

import base64
import gzip
import hashlib
import json
import os
import pathlib
import platform
import signal
import statistics
import subprocess
import sys
import tempfile
import time
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCHEMA = 1
CORPUS_VERSION = 2
SEED = 1729
MODES = ("parse", "generate", "serialize", "apply-inplace", "apply-copy", "generate-serialize", "roundtrip")
FLAGS = ("same-reference", "source-mutable", "target-mutable")
REFERENCE = "7ccc425d3e58da374c9af600074c6ff223089fe8"


def encoded(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False, sort_keys=True,
                      separators=(",", ":")).encode("ascii")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def corpus(profile="quick"):
    cases = []

    def add(family, name, source, target, quick=False, flags=()):
        first = source if isinstance(source, bytes) else encoded(source)
        second = target if isinstance(target, bytes) else encoded(target)
        cases.append(dict(id=f"v{CORPUS_VERSION}/{family}/{name}/seed-{SEED}",
                          family=family, name=name, source=first, target=second,
                          quick=quick, flags=list(flags)))

    for n in (10, 1000, 10000):
        stable = {f"k{i:05d}": f"value-{(i * 6364136223846793005 + SEED) % 1000000007}" for i in range(n)}
        add("unchanged", f"separate-n{n}", stable, stable, n == 10)
        if n == 1000:
            add("unchanged", f"same-reference-n{n}", stable, stable, flags=("same-reference",))
        for position in (0, n - 1):
            changed = dict(stable, **{f"k{position:05d}": "changed"})
            add("sparse", f"object-n{n}-index{position}", stable, changed, n == 1000 and position == n - 1)
        additions = max(1, n * 3 // 10)
        target = dict(stable, **{f"new{i:05d}": f"unmatched-{i}" for i in range(additions)})
        add("copies", f"miss-n{n}-add{additions}", stable, target, n == 1000)
        if n <= 1000:
            churn = {key: value for i, (key, value) in enumerate(stable.items()) if i % 3}
            churn.update({f"renamed{i}": stable[f"k{i:05d}"] for i in range(0, n, 3)})
            add("objects", f"rename-n{n}", stable, churn, n == 10)
            add("dense", f"unrelated-n{n}", stable, {f"other{i}": i for i in range(n)})
        array = list(range(n))
        edits = {
            "append": array + [-1], "prepend": [-1] + array,
            "insert": array[:n // 2] + [-1] + array[n // 2:],
            "delete": array[:n // 2] + array[n // 2 + 1:],
            "replace": array[:n // 2] + [-1] + array[n // 2 + 1:],
            "rotate": array[1:] + array[:1], "reverse": array[::-1],
        }
        for edit, target in edits.items():
            add("arrays", f"{edit}-n{n}", array, target, n == 1000 and edit == "prepend")
    for depth in (8, 64):
        first, second = {"value": 1}, {"value": 2}
        for _ in range(depth):
            first, second = {"branch": first, "stable": [0, 1, 2]}, {"branch": second, "stable": [0, 1, 2]}
        add("sparse", f"deep-{depth}", first, second, depth == 8)
    for kind, value in (
        ("string", "x" * 10000), ("number", 9007199254740993),
        ("array", list(range(100))), ("object", {f"k{i}": i for i in range(100)}),
    ):
        source = {"stable": value}
        target = dict(source, **{f"added{i}": value for i in range(30)})
        add("copies", f"hit-{kind}-bytes{len(encoded(value))}-add30", source, target, kind == "string")
    long_path = "long/~" * 20
    add("encoding", "tiny-value-long-path", {long_path: 1}, {long_path: 1, "added": 1}, True)
    add("encoding", "equivalent-candidates", {f"k{i}": "same" for i in range(100)},
        dict({f"k{i}": "same" for i in range(100)}, added="same"))
    # Copy lookup must cover hits, misses, bounded-fingerprint collisions, and
    # index setup. Compare every library revision with this same v2 corpus.
    for kind in ("string", "array", "object", "numeric-array", "numeric-object", "prefix-collision"):
        n = 64 if kind in ("string", "prefix-collision") else 32
        values = []
        for i in range(n):
            if kind == "string":
                value = f"id-{i:04d}-" + "x" * 256
            elif kind == "array":
                value = [f"id-{i:04d}", list(range(32)), {"flag": True, "body": "x" * 100}]
            elif kind == "object":
                value = {"id": f"id-{i:04d}", "items": list(range(32)), "body": "x" * 100}
            elif kind == "numeric-array":
                value = [i] + [0] * 63
            elif kind == "numeric-object":
                value = {"number": 9007199254740992 + i, "body": "x" * 100}
            else:
                value = "shared-prefix-" * 4 + f"{i:04d}"
            values.append(value)
        source = {f"s{i:04d}": value for i, value in enumerate(values)}
        target = dict(source, **{f"added{i:04d}": values[(i * 17 + 13) % n] for i in range(24)})
        add("copies", f"indexed-hit-{kind}-n{n}-add24", source, target, kind in ("string", "object"))
        if kind == "string":
            add("copies", "indexed-miss-string-n64-add24", source,
                dict(source, **{f"added{i:04d}": f"unmatched-{i:04d}-" + "y" * 256 for i in range(24)}))
    one_query = {f"s{i:04d}": f"id-{i:04d}-" + "x" * 64 for i in range(1000)}
    add("copies", "single-hit-string-n1000-add1", one_query, dict(one_query, added=one_query["s0000"]))
    add("copies", "single-miss-string-n1000-add1", one_query, dict(one_query, added="unmatched-" + "y" * 64))
    donors = {"a": "x" * 1024, "~~~~": "x" * 1024, "long/~" * 10: "x" * 1024}
    donors.update({f"filler{i}": f"other-{i}" for i in range(32)})
    add("encoding", "shortest-escaped-donor-add24", donors,
        dict(donors, **{f"added{i}": "x" * 1024 for i in range(24)}))
    floats = {f"n{i}": 1.23456789 + i for i in range(32)}
    add("encoding", "floating-literal-cost-n32-add24", floats,
        dict(floats, **{f"added{i}": floats[f"n{i}"] for i in range(24)}))
    boundary = {f"a{i}": "x" * i for i in range(1, 10)}
    add("encoding", "literal-copy-byte-boundary", boundary,
        dict(boundary, **{f"added{i}": value for i, value in enumerate(boundary.values())}), True)
    add("arrays", "duplicate-object-mixed-n100", [{"id": i % 7, "value": i % 3} for i in range(100)],
        [{"id": -1, "value": 0}] + [{"id": i % 7, "value": i % 3} for i in range(1, 100)])
    add("dense", "root-object-to-array", {"a": 1}, [True, None, "new"], True)
    nested = {"a": {"items": [1, 2, {"value": "before"}]}}
    changed = {"a": {"items": [1, 2, {"value": "after"}, 3]}}
    for flags in (("source-mutable",), ("target-mutable",), ("source-mutable", "target-mutable")):
        add("mutable", "nested-" + "-".join(flags), nested, changed,
            flags == ("source-mutable", "target-mutable"), flags)
    semantic = ROOT / "Benchmarks/Fixtures/semantic.json"
    for fixture in json.loads(semantic.read_text()):
        # Raw JSON strings keep Unicode spellings and numeric literals intact.
        add("semantics", fixture["name"], fixture["source"].encode(), fixture["target"].encode(), True)
    add("fixtures", "repository-bigexample",
        (ROOT / "Tests/JSONPatchTests/bigexample1.json").read_bytes(),
        (ROOT / "Tests/JSONPatchTests/bigexample2.json").read_bytes(), True)
    return [case for case in cases if profile == "full" or case["quick"]]


def command_output(command, cwd=None):
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def revision(path):
    return {"commit": command_output(["git", "rev-parse", "HEAD"], path),
            "dirty": bool(command_output(["git", "status", "--porcelain"], path)),
            "source_tree": command_output(["git", "rev-parse", "HEAD:Sources"], path),
            "source_diff_sha256": digest((command_output(["git", "diff", "HEAD", "--", "Sources", "Package.swift"], path) or "").encode())}


def environment():
    cpu = command_output(["sysctl", "-n", "machdep.cpu.brand_string"]) if sys.platform == "darwin" else None
    if not cpu and pathlib.Path("/proc/cpuinfo").exists():
        cpu = next((line.split(":", 1)[1].strip() for line in pathlib.Path("/proc/cpuinfo").read_text().splitlines()
                    if line.startswith("model name")), platform.processor())
    return {"system": platform.system(), "os": platform.platform(), "architecture": platform.machine(),
            "cpu": cpu or platform.processor(), "swift": command_output(["swift", "--version"]),
            "xcode": command_output(["xcodebuild", "-version"]) if sys.platform == "darwin" else None,
            "python": platform.python_version(), "zlib": zlib.ZLIB_VERSION,
            "rss_polling_available": resident_bytes(os.getpid()) > 0,
            "build_flags": ["--configuration", "release", "--build-system", "native", "--manifest-cache", "none", "-Xswiftc", "-warnings-as-errors"],
            "compression": {"format": "gzip", "level": 9, "mtime": 0}}


def harness_hash():
    paths = sorted((ROOT / "Benchmarks/Sources").rglob("*.swift"))
    paths += [ROOT / "Benchmarks/Package.swift", ROOT / "Benchmarks/Fixtures/semantic.json",
              pathlib.Path(__file__), ROOT / "Scripts/benchmark-patch-generation.py",
              ROOT / "Scripts/compare-patch-generation.py"]
    return digest(b"".join(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes() for path in paths))


def build(library, build_dir):
    env = os.environ.copy()
    env["JSONPATCH_BENCHMARK_LIBRARY_PATH"] = str(library.resolve())
    build_dir.mkdir(parents=True, exist_ok=True)
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(build_dir / "clang-cache"))
    env.setdefault("SWIFTPM_MODULECACHE_OVERRIDE", str(build_dir / "module-cache"))
    common = ["swift", "build", "--package-path", str(ROOT / "Benchmarks"),
              "--scratch-path", str(build_dir / "build"), "--cache-path", str(build_dir / "cache"),
              "--config-path", str(build_dir / "config"), "--security-path", str(build_dir / "security"),
              "--disable-sandbox", "--configuration", "release", "--build-system", "native", "--manifest-cache", "none",
              "-Xswiftc", "-warnings-as-errors"]
    subprocess.run(common, env=env, check=True, stdout=sys.stderr)
    output = subprocess.run(common + ["--show-bin-path"], env=env, check=True, text=True, capture_output=True)
    return pathlib.Path(output.stdout.strip()) / "PatchGenerationBenchmarks"


def resident_bytes(pid):
    try:
        if sys.platform.startswith("linux"):
            for line in pathlib.Path(f"/proc/{pid}/status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    return int(line.split()[1]) * 1024
        elif sys.platform == "darwin":
            value = command_output(["ps", "-o", "rss=", "-p", str(pid)])
            return int(value) * 1024 if value else 0
    except (OSError, ValueError):
        pass
    return 0


def run_worker(binary, case, mode, settings, directory, memory_only=False, validate_only=False):
    source, target = directory / "source.json", directory / "target.json"
    source.write_bytes(case["source"])
    target.write_bytes(case["target"])
    command = [str(binary), "--source", str(source), "--target", str(target), "--mode", mode,
               "--samples", str(settings["samples"]), "--sample-ms", str(settings["sample_ms"]),
               "--warmup", str(settings["warmup"]), "--max-iterations", str(settings["max_iterations"])]
    command += ["--" + flag for flag in case["flags"]]
    if memory_only:
        command.append("--memory-only")
    if validate_only:
        command.append("--validate-only")
    began = time.monotonic()
    status = None
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            while process.poll() is None:
                if time.monotonic() - began > settings["timeout_seconds"]:
                    status = "timeout"
                elif resident_bytes(process.pid) > settings["memory_limit_mb"] * 1024 * 1024:
                    status = "memory-limit"
                if status:
                    break
                time.sleep(0.025)
        finally:
            # A timeout, memory breach, or interrupted parent must not leave a worker behind.
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
        stdout.seek(0)
        stderr.seek(0)
        error = stderr.read().decode(errors="replace")[-6000:]
        if status or process.returncode:
            return {"status": status or "failed", "error": error, "exit_code": process.returncode}
        try:
            result = json.loads(stdout.read())
            validate_worker(result, mode, memory_only, validate_only)
            if not memory_only and not validate_only and len(result["samples_ns"]) != settings["samples"]:
                raise ValueError("Wrong sample count")
            if not 1 <= result["iterations_per_sample"] <= settings["max_iterations"]:
                raise ValueError("Invalid calibrated iteration count")
            if result["source_bytes"] != len(case["source"]) or result["target_bytes"] != len(case["target"]):
                raise ValueError("Wrong fixture byte counts")
            patch = base64.b64decode(result.pop("patch_data_base64"), validate=True)
            if len(patch) != result["patch_bytes"]:
                raise ValueError("Patch byte count mismatch")
            result["patch_gzip_bytes"] = len(gzip.compress(patch, compresslevel=9, mtime=0))
            result["patch_sha256"] = digest(patch)
            result["status"] = "passed"
            if result["peak_rss_bytes"] > settings["memory_limit_mb"] * 1024 * 1024:
                result["status"] = "memory-limit"
            return result
        except (ValueError, KeyError, TypeError) as error:
            return {"status": "invalid-result", "error": str(error)}


def validate_worker(result, mode, memory_only=False, validate_only=False):
    if result["worker_schema_version"] != 1 or result["mode"] != mode or result["validation"] != "passed":
        raise ValueError("Worker schema, mode, or validation mismatch")
    if result["memory_only"] != memory_only:
        raise ValueError("Wrong worker measurement kind")
    samples = result["samples_ns"]
    if not isinstance(samples, list) or (not memory_only and not validate_only and not samples):
        raise ValueError("Missing timing samples")
    if any(not isinstance(value, (int, float)) or not 0 < value < float("inf") for value in samples):
        raise ValueError("Invalid timing sample")
    for key in ("peak_rss_bytes", "patch_bytes", "source_bytes", "target_bytes", "source_nodes", "target_nodes"):
        if not isinstance(result[key], int) or result[key] < 0:
            raise ValueError("Invalid " + key)
    if not isinstance(result["checksum"], str) or not result["checksum"].isdigit():
        raise ValueError("Invalid checksum")
    if not isinstance(result["operation_counts"], dict) or any(
            key not in ("add", "remove", "replace", "move", "copy", "test")
            or not isinstance(value, int) or value < 0 for key, value in result["operation_counts"].items()):
        raise ValueError("Invalid operation counts")


def case_metadata(case):
    return {key: value for key, value in case.items() if key not in ("source", "target", "quick")} | {
        "source_sha256": digest(case["source"]), "target_sha256": digest(case["target"])}


def median(samples):
    return statistics.median(samples) if samples else None


def summarize(records):
    passed = [record for record in records if record["status"] == "passed"]
    times = [median(record["samples_ns"]) for record in passed if record.get("samples_ns")]
    return {"process_medians_ns": times, "median_ns": median(times),
            "min_process_median_ns": min(times) if times else None,
            "max_process_median_ns": max(times) if times else None,
            "peak_rss_bytes": max((r.get("measurement_peak_rss_bytes", 0) for r in passed), default=0),
            "patch_bytes": [r["patch_bytes"] for r in passed],
            "patch_gzip_bytes": [r["patch_gzip_bytes"] for r in passed],
            "passed_processes": len(passed), "failed_processes": len(records) - len(passed)}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")


def report_run(run):
    lines = ["# Patch generation benchmark results", "", f"Library: `{run['library']['commit']}`.",
             f"Platform: {run['environment']['os']}; {run['environment']['architecture']}.", "",
             "Times are medians of per-process medians of batch-average operation times.",
             "Memory is a dedicated fresh process's peak RSS, including runtime, input preparation, and prepared patch where required; captured before validation/reporting.", "",
             "| Case | Measurement | Time (ms) | Process range (ms) | Peak RSS (MiB) | Patch bytes | Status |",
             "| --- | --- | ---: | ---: | ---: | ---: | --- |"]
    for item in run["results"]:
        summary = item["summary"]
        timing = summary["median_ns"]
        spread = "—" if timing is None else f"{summary['min_process_median_ns']/1e6:.4f}–{summary['max_process_median_ns']/1e6:.4f}"
        sizes = summary["patch_bytes"]
        status = "passed" if not summary["failed_processes"] else "FAILED"
        if any(r.get("iteration_limit_reached") for r in item["processes"]):
            status += "; calibration limit"
        lines.append(f"| {item['case']['id']} | {item['mode']} | {'—' if timing is None else f'{timing/1e6:.4f}'} | {spread} | {summary['peak_rss_bytes']/1048576:.1f} | {min(sizes) if sizes else '—'}–{max(sizes) if sizes else '—'} | {status} |")
    lines += ["", "Raw process samples, compression sizes, validation failures, fixture hashes, and toolchain details are in the JSON report.",
              "Results are informational. Absolute timings from different machines or toolchains are not comparable.", ""]
    return "\n".join(lines)
