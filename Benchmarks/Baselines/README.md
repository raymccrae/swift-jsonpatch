# v2.0.0 patch generation baseline

Reference library commit: `7ccc425d3e58da374c9af600074c6ff223089fe8`.

Capture the release against itself with the same harness and at least three alternating process pairs. Commit compact summaries and reproduction metadata here; retain full process samples as workflow artifacts or local reports. Keep machine/toolchain results separate. Never compare absolute times between macOS and Linux or between different hosts.

The benchmark workflow captures reference reports on both operating systems. The main benchmark README documents reproduction commands, measurement boundaries, and limits. Baseline reports must state which corpus/profile and modes were measured, the observed baseline noise, validation status, and any missing or failed cases.

## Local macOS reference

The [Swift 6.4.2 macOS summary](v2.0.0-macos-arm64-swift6.4.2.md) and [machine-readable metadata](v2.0.0-macos-arm64-swift6.4.2.json) were captured on November 18, 2026, on an Apple M5 Pro with Xcode 27.2 and macOS 27.0.1.

The capture covers all 18 quick cases and all seven measurements: 126 combinations, each with three independent baseline/candidate process pairs and dedicated memory workers. All passed. The separate full correctness matrix passed all 236 case/mutability combinations. The median observed absolute process-pair timing deviation was 2.16%; the maximum was 42.26%. Inspect individual cases before judging a change; the maximum is not a universal threshold, and small timings remain sensitive to overhead.

Reproduce the capture and summary from the repository root:

```sh
python3 Scripts/benchmark-patch-generation.py \
  --library-ref v2.0.0 --baseline-ref v2.0.0 \
  --processes 3 --samples 5 --sample-ms 5 \
  --output Benchmarks/Results/reference
python3 Scripts/summarize-patch-generation-baseline.py \
  Benchmarks/Results/reference/baseline.json \
  Benchmarks/Results/reference/candidate.json \
  --output Benchmarks/Baselines/v2.0.0-local.json
```

The initial harness capture records a dirty working tree and its exact content hash because it preceded the implementation commit. Its measured library is a clean Git export of v2.0.0, with a separate library content hash. Implementation commit `8c1b3f9` reproduces that harness hash. Full local raw reports remain ignored under `Benchmarks/Results/reference-final/`; re-run to obtain fresh samples rather than comparing against this compact summary.

This reference uses corpus version 1. Stage 3 expands the harness to corpus version 2; fresh runs from that checkout use its 21 quick/71 full cases. For exact reproduction of the historical capture, use the recorded version 1 harness rather than comparing reports across harness hashes. Stage 3's incremental and release comparisons use version 2 on both sides and are documented in its [assessment](../Reports/stage3-macos-arm64-swift6.4.2.md).

## Pending cross-platform capture

Linux and the supported Xcode 16.2/26.3 matrix have not been run for this implementation. The feature branch is local at the user's request, and this host has no Linux runtime. The configured workflow can capture those reference reports when the branch is published. Stage 1's cross-platform baseline acceptance criterion remains pending until those jobs pass and their reports are reviewed. Hosted-runner timings will be informational and must not be compared directly with this machine's absolute timings.

## Local verification

- Library correctness: all 86 tests passed in both Debug and Release with compiler warnings treated as errors.
- Benchmark support: all seven Swift tests and all 12 Python regression tests passed.
- Corpus correctness: all 236 full-corpus source/target mutability combinations passed against the exported release.
- Reference measurements: both halves of all 126 quick-corpus measurement combinations passed, with three process pairs each and separate memory workers.
- The working library's source and package-manifest content hash matches the measured release snapshot. No generator or library implementation changes are included.
