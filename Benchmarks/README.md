# Measure patch generation

This standalone package measures the public JSONPatch APIs without changing the library package or its distributed products. It requires Swift 6, Python 3.9 or newer, and macOS 14 or Linux. It has no third-party dependencies.

## Run the suite

From the repository root, validate the quick corpus in all four source/target mutability combinations:

```sh
python3 Scripts/benchmark-patch-generation.py --validate-only
```

Capture a reproducible release baseline and its observed noise with three alternating pairs of independent processes:

```sh
python3 Scripts/benchmark-patch-generation.py \
  --library-ref v2.0.0 --baseline-ref v2.0.0 \
  --processes 3 --output Benchmarks/Results/reference
```

The script exports each Git revision to a temporary directory, builds it once in Release using this harness, and deletes the exports afterward. It does not switch branches or modify the measured library. The harness stays the same when library revisions differ.

Measure the working tree against the release, or select one case and measurement:

```sh
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref v2.0.0 --output Benchmarks/Results/candidate
python3 Scripts/benchmark-patch-generation.py \
  --case 'arrays/prepend-n1000' --mode generate \
  --output Benchmarks/Results/prepend
```

For two existing checkouts, use `--baseline-library-path /path/to/baseline --library-path /path/to/candidate`. Paths are passed as arguments, not shell fragments. `--library-ref` and `--baseline-ref` optionally select commits within their respective repositories. Record and inspect the dirty state when measuring a working tree.

Use `--profile full` to include the larger sizes and additional edit shapes. Full runs can take substantially longer: every case and measurement has independent processes, validation, and a separate memory process. `--case` accepts a substring or glob and can be repeated. `--mode` accepts `parse`, `generate`, `serialize`, `apply-inplace`, `apply-copy`, `generate-serialize`, `roundtrip`, or `all`.

For a brief execution check, reduce work with `--processes 1 --samples 2 --sample-ms 1`. Such results are explicitly exploratory; use at least three process pairs and repeat measurements on an idle machine before making a performance decision.

## Understand measurement boundaries

| Measurement | Timed work |
| --- | --- |
| `parse` | Parse both input byte strings and wrap their values as `JSONElement`. |
| `generate` | Construct a patch from prepared elements. Includes per-call generator work. |
| `serialize` | Serialize a prepared patch using default writer options. |
| `apply-inplace` | Apply a prepared patch to a fresh mutable source, restored outside timing. |
| `apply-copy` | Apply a prepared patch to the prepared source using `.applyOnCopy`; copying is timed. |
| `generate-serialize` | Parse both byte strings, generate, and serialize a patch. |
| `roundtrip` | Parse both documents, generate and serialize the patch, decode it, parse a fresh mutable source, apply, and serialize the result. |

The same-reference case shares source and target references for generation and prepared-patch construction. Operations that start from bytes still parse their inputs separately. Mutability flags apply to prepared inputs and explicit parsing; `generate-serialize` uses the Data initializer with its documented immutable parsing options.

Each invocation consumes the result and releases temporary outputs inside the worker call. On Darwin, the invocation also drains an autorelease pool before stopping the timer. In-place input setup and release are outside the interval. The complete round trip includes its parsing and temporary-output destruction. The harness does not time fixture generation, process startup, compilation, full correctness checks, or gzip compression.

Timing uses a monotonic clock, three warmups by default, and bounded batch calibration. Defaults are 10 samples, a target of 20 ms of accumulated operation time per sample, and at most 10,000 iterations per sample. The calibration result is reused for that process's samples. A shortfall at the iteration cap is recorded. Reported samples are batch-average operation times, not request-latency percentiles. Each invocation has two clock reads; very small cases may remain sensitive to timer and wrapper overhead.

The runner explicitly selects SwiftPM's `native` build system for consistent Swift 6.0/6.2 and local build behavior, and disables manifest caching so a changed library-path environment variable cannot select a previous checkout. Swift 6.4 warns that this build system is deprecated. Both choices are recorded in the build flags; re-establish the baseline if the build system or compiler options change.

For paired runs, baseline and candidate order alternates between process pairs. Cases and measurements run serially. The comparison reports observed process-pair ranges and labels identical library contents as a noise measurement. It refuses different environments, toolchains, harness contents, measurement settings, or fixture contents. Separate report files cannot prove that runs alternated; use the runner's paired mode for decisions.

## Read results

Output is ignored under `Benchmarks/Results/`. A single run creates `run.json` and `run.md`. A paired run creates `baseline.json`, `candidate.json`, and their Markdown reports, plus `comparison.md`. Regenerate a comparison with:

```sh
python3 Scripts/compare-patch-generation.py \
  Benchmarks/Results/candidate/baseline.json \
  Benchmarks/Results/candidate/candidate.json \
  --output Benchmarks/Results/candidate/comparison.md
```

JSON schema version 1 records:

- Harness content hash, corpus version and seed, Git revisions and dirty state, library source tree and actual content hash, build flags, machine, toolchain, and compression versions.
- Case parameters, input SHA-256 hashes, bytes, node counts, and depth.
- Every process's raw samples, iteration count, checksum, operation counts, raw/gzip patch bytes, and patch hash. Patch order can vary with hashing; patch bytes and compressed size are recorded for every process rather than requiring identical patch sequences.
- Dedicated memory measurements, process-pair identifiers, failure messages, and per-case summaries. Summary time is the median of process medians; its range describes independent process variation.

Memory comes from one operation in a separate fresh process, captured before validation and reporting. Peak RSS includes the runtime, prepared input documents, and a prepared patch for serialize/apply measurements. It is not an allocation count, a delta from an unrelated high-water mark, or a measurement of the library alone. Darwin bytes and Linux KiB are normalized to bytes. For allocation attribution or transient peaks, use a profiler.

The parent polls resident memory and enforces a default 1,024 MiB RSS ceiling and 60-second process timeout. Short-lived peaks can be missed by polling; the worker's recorded peak is also checked against the ceiling. These are experimental work limits, not a hard operating-system memory reservation. Limit breaches and failed cases stay visible in reports and make the runner fail.

The environment metadata records whether RSS polling is available. In a restricted sandbox that denies `ps` or `/proc`, only the completed worker's peak can be checked; timeout enforcement still applies. Use a host with polling available for memory-limit experiments.

Gzip uses level 9 and `mtime=0`; Python and zlib versions are recorded. Sizes are secondary to raw patch bytes and are not assumed to represent every transport. No combined performance score or timing threshold is enforced.

## Corpus and correctness

The quick corpus covers unchanged documents, sparse updates, object churn, copy hits/misses, encoding costs, array edits, dense changes, mutable containers, semantic boundaries, and the repository's existing large fixture. Full adds 10,000-entry documents, deeper nesting, more edit types, and more reusable value types. Case IDs include a corpus version, parameters, and a fixed seed. Deterministic arithmetic and ASCII JSON encoding avoid platform-dependent fixture generation. Semantic literals are stored in [Fixtures/semantic.json](Fixtures/semantic.json).

Corpus version 4 has 36 quick cases and 94 full cases. It retains the earlier copy, encoding, and array workloads and adds complete object changes, change densities from 10% to 99%, large changed strings, repeated target containers, and sparse edits beside a one-megabyte unchanged payload. Existing input bytes are retained, but IDs and the harness hash change. Compare both library revisions with the same harness; use the recorded stage 2, 3, or 4 commit to reproduce historical corpus reports.

Before and after timing, an independent comparator checks round trips, source/target preservation, and patch reuse. Its equality is implemented without the generator's helpers: Unicode scalar keys and strings, Boolean/number separation, and decimal comparisons without converting integers through Double. The corpus bounds numbers to values representable by Foundation and Decimal; arbitrary-precision numeric JSON is outside this harness's scope. Comparator regression tests explicitly cover neighboring large integers and composed/decomposed keys. Each mode must succeed; a failure is never interpreted as a fast measurement.

Fixture ingestion protects object names before Foundation parses them: names are temporarily encoded as ASCII, then restored as literal CFString-backed keys in recursively mutable or immutable containers. This prevents corelibs Foundation from merging composed and decomposed names before the independent checks can inspect them. Foundation still validates JSON syntax and parses scalar values. Regression tests check nested containers, mixed literal/escaped names, Boolean and integer identity, transport-name collisions, serialization, and malformed input.

The fixture reader runs on both platforms, so parse and round-trip measurements include this support work. Its source is covered by the harness content hash; rerun both revisions with this harness rather than comparing its timings with earlier reports. Input bytes and corpus version 4 are unchanged. Public Data-initializer measurements still exercise the library's own parsing.

The round-trip measurement uses the library's `JSONSerialization.data(with: JSONElement)` extension for the final document too. This keeps its encoding within the library under test. An exported release with lossy Linux wire-format handling can therefore fail correctness checks even when the current candidate passes. Such failures remain failures in the raw reports; they are not speed measurements or evidence against the current generator.

Run the harness tests and the full correctness matrix with:

```sh
python3 Scripts/test-patch-generation-benchmarks.py
swift test --package-path Benchmarks -Xswiftc -warnings-as-errors
python3 Scripts/benchmark-patch-generation.py --profile full --validate-only
python3 Scripts/validate-patch-generation-candidate.py --profile full
```

The candidate-validation command checks both current policies in all four mutability combinations. It uses the working library for the default and a temporary `prefer-smaller` adapter for the public option, with no release revision selected. Reports go to `Benchmarks/Results/candidate-validation/default/` and `prefer-smaller/`. Both policies are attempted if the default fails; either validation failure or an adapter-export failure makes the command fail.

The benchmark workflow is configured for Swift 6.0.3 and 6.2 Linux, and Xcode 16.2 and 26.3 macOS. It runs candidate validation for both policies, separately validates v2.0.0, captures the release baseline/noise, and uploads reports even after failures. Candidate validation uses the quick corpus by default and the full corpus for a full `workflow_dispatch` run. Hosted-runner timing is informational. Repeat on a consistent idle machine before assessing regressions.

Curated reference summaries and their reproduction details belong in [Baselines](Baselines/README.md). Retain raw reports as artifacts. A reference run is an observation on its recorded machine, not a portable performance promise.

The [stage 2 macOS assessment](Reports/stage2-macos-arm64-swift6.4.2.md) compares shared traversal and planning against v2.0.0, including the measured tradeoffs and reproduction commands. Its compact comparison data lives beside the report; raw samples stay under the ignored results directory.

The [stage 3 assessment](Reports/stage3-macos-arm64-swift6.4.2.md) measures copy indexing and size-aware choices against stage 2 and the release. It records small-case regressions and object-equality order sensitivity as well as improvements. For untimed source/query counts, value sizes, hit rates, and equality work, run `python3 Scripts/diagnose-patch-generation.py`. That tool compiles a temporary instrumented copy and leaves the checkout unchanged; it fails explicitly if its stage 3 instrumentation markers no longer match. Keep diagnostic runs separate from timing runs.

The [stage 4 assessment](Reports/stage4-macos-arm64-swift6.4.2.md) measures bounded array matching against stage 3 and the release. It includes patch quality, application costs, difficult-array overhead, and copy-source safety. Add `--include-arrays --case arrays/` to the diagnostic command for per-array work, trace size, retained affixes/anchors, and fallback counts. These counters come from a temporary instrumented copy and are absent from the timed library.

The [stage 5 assessment](Reports/stage5-macos-arm64-swift6.4.2.md) evaluates adaptive replacement, estimation overhead, and public options. `Scripts/evaluate-patch-generation-strategy.py` exports experimental libraries into new directories without editing the checkout. Its `prefer-smaller` adapter calls the public `generationOptions: [.preferSmallerPatch]` overload through the harness's existing initializer calls. Compare variants with `--library-path`, and keep their source hashes separate from the retained implementation. The report documents each strategy and its limits. For large sparse inputs, in-place application can spend substantial wall time restoring inputs outside the timer; `--max-iterations 1000` bounds that repeated setup, with any calibration shortfall retained in the results.

Export a compact reference summary after a successful three-pair release-versus-release run:

```sh
python3 Scripts/summarize-patch-generation-baseline.py \
  Benchmarks/Results/reference/baseline.json \
  Benchmarks/Results/reference/candidate.json \
  --output Benchmarks/Baselines/v2.0.0-local.json
```

The summary uses a separate schema (`summary_schema_version: 1`) and retains fixture metadata, process medians, memory and size summaries, operation counts, and observed noise ratios. Re-run the benchmark to make a future comparison; the compact summary does not replace raw timing samples. The exporter rejects incomplete, failed, non-release, and insufficient-process runs.
