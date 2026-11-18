#!/usr/bin/env python3
"""Compare compatible benchmark reports without hiding failed or missing cases."""
from __future__ import annotations

import argparse
import json
import pathlib
import statistics
import sys

import patch_generation_benchmark as support


def compare(first, second):
    if first["schema_version"] != support.SCHEMA or second["schema_version"] != support.SCHEMA:
        raise ValueError("Unsupported result schema")
    for key in ("system", "os", "architecture", "cpu", "swift", "xcode", "build_flags", "python", "zlib", "compression", "rss_polling_available"):
        if first["environment"][key] != second["environment"][key]:
            raise ValueError("Incompatible environment: " + key)
    if first["harness"]["sha256"] != second["harness"]["sha256"]:
        raise ValueError("Use the same harness to compare library revisions")
    if first["settings"] != second["settings"]:
        raise ValueError("Incompatible measurement settings")
    def rows(run):
        result = {(item["case"]["id"], item["mode"]): item for item in run["results"]}
        if len(result) != len(run["results"]):
            raise ValueError("Duplicate case/measurement")
        return result
    left, right = rows(first), rows(second)
    same_library = first["library"]["content_sha256"] == second["library"]["content_sha256"]
    lines = ["# Patch generation comparison", "",
             f"Baseline: `{first['library']['commit']}`. Candidate: `{second['library']['commit']}`.",
             "", "Identical library contents: this measures baseline noise." if same_library else "Timings are exploratory; confirm differences against repeated baseline noise measurements.",
             "", "Ratios below 1 favor the candidate. Process-pair ranges describe observed variation, not confidence intervals or latency percentiles.",
             "", "| Case | Measurement | Candidate / baseline | Pair ratio range | Patch byte change | Peak RSS change | Status |",
             "| --- | --- | ---: | ---: | ---: | ---: | --- |"]
    ratios_for_noise = []
    for key in sorted(left.keys() | right.keys()):
        if key not in left or key not in right:
            lines.append(f"| {key[0]} | {key[1]} | — | — | — | — | MISSING |")
            continue
        a, b = left[key], right[key]
        if a["case"] != b["case"]:
            raise ValueError("Fixture or parameters differ: " + key[0])
        processes_a = {p["pair"]: p for p in a["processes"]}
        processes_b = {p["pair"]: p for p in b["processes"]}
        if processes_a.keys() != processes_b.keys():
            raise ValueError("Missing independent process pair")
        if a["summary"]["failed_processes"] or b["summary"]["failed_processes"]:
            lines.append(f"| {key[0]} | {key[1]} | — | — | — | — | FAILED |")
            continue
        ratios = []
        for pair in processes_a:
            before, after = processes_a[pair], processes_b[pair]
            if before.get("samples_ns") and after.get("samples_ns"):
                ratios.append(statistics.median(after["samples_ns"]) / statistics.median(before["samples_ns"]))
        if not ratios:
            lines.append(f"| {key[0]} | {key[1]} | — | — | — | — | validation only |")
            continue
        status = "informational" if len(ratios) >= 3 else "exploratory: fewer than 3 pairs"
        if any(p.get("iteration_limit_reached") for p in a["processes"] + b["processes"]):
            status += "; calibration limit"
        median_ratio = statistics.median(ratios)
        if same_library:
            ratios_for_noise.extend(abs(ratio - 1) for ratio in ratios)
        byte_delta = statistics.median(b["summary"]["patch_bytes"]) - statistics.median(a["summary"]["patch_bytes"])
        memory_delta = (b["summary"]["peak_rss_bytes"] - a["summary"]["peak_rss_bytes"]) / 1048576
        lines.append(f"| {key[0]} | {key[1]} | {median_ratio:.3f} | {min(ratios):.3f}–{max(ratios):.3f} | {byte_delta:+g} | {memory_delta:+.1f} MiB | {status} |")
    if ratios_for_noise:
        lines += ["", f"Observed absolute process-pair timing deviation for this identical-library run: median {statistics.median(ratios_for_noise):.1%}, maximum {max(ratios_for_noise):.1%}.",
                  "Inspect per-case ranges and repeat on an idle machine; this is an observed noise sample, not a universal regression threshold."]
    lines += ["", "Review generation, application, compressed/raw size, and memory by workload family. No aggregate performance score or automatic timing gate is applied.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=pathlib.Path)
    parser.add_argument("candidate", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    report = compare(json.loads(args.baseline.read_text()), json.loads(args.candidate.read_text()))
    if args.output:
        args.output.write_text(report)
    else:
        print(report)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(f"Comparison failed: {error}", file=sys.stderr)
        sys.exit(1)
