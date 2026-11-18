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

The initial harness capture records a dirty working tree and its exact content hash because it preceded the implementation commit. Its measured library is a clean Git export of v2.0.0, with a separate library content hash. The checked-in harness reproduces that hash. Full local raw reports remain ignored under `Benchmarks/Results/reference-final/`; re-run to obtain fresh samples rather than comparing against this compact summary.

Linux and the supported Xcode matrix are captured independently by the benchmark workflow. Their hosted-runner timings are informational and must not be compared directly with this machine's absolute timings.
