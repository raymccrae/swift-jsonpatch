#!/usr/bin/env python3
"""Export a compact, validated release-reference summary from a paired noise run."""
import argparse
import importlib.util
import json
import pathlib
import statistics
import sys

import patch_generation_benchmark as support

spec = importlib.util.spec_from_file_location("comparison", pathlib.Path(__file__).with_name("compare-patch-generation.py"))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


def summarize(baseline, candidate):
    comparison.compare(baseline, candidate)
    for run in (baseline, candidate):
        if run["library"]["commit"] != support.REFERENCE or run["library"]["dirty"]:
            raise ValueError("Reference summary requires a clean exported v2.0.0 library")
        if run["settings"]["processes"] < 3 or run["settings"]["validate_only"]:
            raise ValueError("Reference summary requires at least three timed process pairs")
    if baseline["library"]["content_sha256"] != candidate["library"]["content_sha256"]:
        raise ValueError("Noise measurements must use identical library contents")
    other = {(r["case"]["id"], r["mode"]): r for r in candidate["results"]}
    if len(other) != len(baseline["results"]):
        raise ValueError("Incomplete reference run")
    rows = []
    deviations = []
    for row in baseline["results"]:
        peer = other[(row["case"]["id"], row["mode"])]
        if row["summary"]["failed_processes"] or peer["summary"]["failed_processes"]:
            raise ValueError("Reference run contains failed cases")
        before = {p["pair"]: p for p in row["processes"]}
        after = {p["pair"]: p for p in peer["processes"]}
        expected_pairs = set(range(baseline["settings"]["processes"]))
        if before.keys() != expected_pairs or after.keys() != expected_pairs:
            raise ValueError("Missing reference process pair")
        ratios = [statistics.median(after[p]["samples_ns"]) / statistics.median(before[p]["samples_ns"])
                  for p in sorted(before)]
        deviations.extend(abs(r - 1) for r in ratios)
        sample = row["processes"][0]
        rows.append({"case": row["case"], "mode": row["mode"], "summary": row["summary"],
                     "noise_pair_ratios": ratios,
                     "shape": {key: sample[key] for key in ("source_bytes", "target_bytes", "source_nodes", "target_nodes", "source_depth", "target_depth")},
                     "operation_counts": [p["operation_counts"] for p in row["processes"]],
                     "calibration_limit_reached": any(p["iteration_limit_reached"] for p in row["processes"] + peer["processes"])})
    return {"summary_schema_version": 1, "captured_at": baseline["captured_at"],
            "library": baseline["library"], "harness": baseline["harness"],
            "environment": baseline["environment"], "settings": baseline["settings"],
            "observed_noise": {"median_absolute_pair_deviation": statistics.median(deviations),
                               "maximum_absolute_pair_deviation": max(deviations)},
            "validation": "passed", "rows": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=pathlib.Path)
    parser.add_argument("candidate", type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--print-json", action="store_true", help="Also write the compact summary to stdout for CI log retrieval")
    args = parser.parse_args()
    first, second = json.loads(args.baseline.read_text()), json.loads(args.candidate.read_text())
    summary = summarize(first, second)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Keep generated references reviewable: metadata is indented and each
    # case/measurement occupies one line instead of expanding thousands of lines.
    metadata = {key: value for key, value in summary.items() if key != "rows"}
    header = json.dumps(metadata, indent=2, sort_keys=True, allow_nan=False)
    rows = ",\n".join("    " + json.dumps(row, sort_keys=True, separators=(",", ":"), allow_nan=False)
                       for row in summary["rows"])
    args.output.write_text(header[:-2] + ',\n  "rows": [\n' + rows + '\n  ]\n}\n')
    markdown = args.output.with_suffix(".md")
    markdown.write_text(support.report_run(first) + "\n" + comparison.compare(first, second))
    if args.print_json:
        print("BASELINE_SUMMARY_JSON=" + json.dumps(summary, separators=(",", ":"), sort_keys=True))
    else:
        print(f"Wrote {args.output} and {markdown}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(f"Reference summary failed: {error}", file=sys.stderr)
        sys.exit(1)
