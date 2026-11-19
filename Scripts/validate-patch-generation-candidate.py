#!/usr/bin/env python3
"""Validate both current generation policies without selecting a release revision."""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import tempfile

import patch_generation_benchmark as support


def validate(profile, output):
    runner = str(support.ROOT / "Scripts/benchmark-patch-generation.py")
    exporter = str(support.ROOT / "Scripts/evaluate-patch-generation-strategy.py")
    common = [sys.executable, runner, "--profile", profile, "--validate-only"]
    default = subprocess.run(common + ["--library-path", str(support.ROOT),
                                      "--output", str(output / "default")])
    # Still validate the option if the default fails, retaining both reports.
    with tempfile.TemporaryDirectory(prefix="jsonpatch-candidate-policy-") as temporary:
        library = str(pathlib.Path(temporary) / "library")
        exported = subprocess.run([sys.executable, exporter, "--strategy", "prefer-smaller", "--output", library])
        if exported.returncode:
            return 1
        option = subprocess.run(common + ["--library-path", library,
                                         "--output", str(output / "prefer-smaller")])
    return int(default.returncode != 0 or option.returncode != 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("quick", "full"), default="quick")
    parser.add_argument("--output", type=pathlib.Path,
                        default=support.ROOT / "Benchmarks/Results/candidate-validation")
    args = parser.parse_args()
    return validate(args.profile, args.output.resolve())


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError) as error:
        print(f"Candidate validation failed: {error}", file=sys.stderr)
        sys.exit(1)
