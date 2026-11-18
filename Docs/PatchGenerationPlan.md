# Improve patch generation with measured tradeoffs

Build a reproducible benchmark suite before changing the generator. Use it to improve generation time, patch size, application time, and memory use while preserving JSON Patch correctness and the existing public API.

This is an implementation plan. Stage 1's harness and commands are implemented in the [benchmark suite](../Benchmarks/README.md); its reference reports are tracked under [Baselines](../Benchmarks/Baselines/README.md). Stages 2–5 remain proposed. Implement each stage as a separate, reviewable change, and retain only improvements supported by measurements.

Use `feature/patch-generation` for this proposal, based on `develop`. Create subsequent `feature/<topic>` branches from `develop` for selected implementation stages. Merge selected work into `develop`; reserve `master` for released versions. Follow the [repository workflow](../AGENTS.md).

## Starting point

The reference implementation is v2.0.0, commit `7ccc425d3e58da374c9af600074c6ff223089fe8`.

The [generator](../Sources/JSONPatch/JSONPatchGenerator.swift) performs an unchanged-value traversal followed by a difference traversal. Both use recursive equality checks. Each addition searches unchanged candidates for a possible `copy`. Arrays are compared by position, with removals and additions at the end.

The [generator tests](../Tests/JSONPatchTests/JSONPatchGeneratorTests.swift) cover large documents, array transfers, Unicode property identity, and copy candidates. `testPerformanceGenerate` executes generation but does not measure performance. Keep it as a correctness smoke test, rename it to describe that role, and put performance measurement in a separate executable.

Temporary experiments suggest that sharing traversal work and indexing copy candidates can reduce generation time without losing compact copies. They also show that a `copy` can be larger than an `add`, and that a front insertion can produce many positional replacements. Treat those results as hypotheses. Do not use their timings as the project's performance baseline or copy the experimental implementation into production.

## 1. Establish the benchmark suite and baseline

### Keep benchmark infrastructure separate from the library

Create a standalone Swift package under `Benchmarks/`, using a local path dependency on the repository root. Use Swift 6 and Foundation for the first implementation. Keep benchmark-only code, platform requirements, and dependencies out of the library package and its distributed products.

Use this proposed layout:

```text
Benchmarks/
  Package.swift
  README.md
  Sources/PatchGenerationBenchmarks/
  Fixtures/
  Baselines/
Scripts/
  benchmark-patch-generation.py
  compare-patch-generation.py
```

The Swift executable builds inputs, runs one selected case and measurement, and emits structured results. Python scripts use the standard library to build once, launch independent measurement processes, collect results, and compare revisions. Run cases serially. Build time and fixture generation are outside measured operations.

Benchmark public APIs. Do not expose generator internals to support the harness. Add temporary internal counters or profiling hooks only when investigating a specific cost, and measure production performance without them.

Document commands for a quick run, full run, one case, one measurement, and comparison with a baseline. Generate machine-readable JSON results and a Markdown comparison report. Ignore local raw output in Git; commit a small reference summary and its reproduction metadata under `Benchmarks/Baselines/`.

### Measure distinct operations

For each applicable case, collect the following measurements. Label the boundary precisely so results from different operations are never combined into one timing.

| Measurement | Included work |
| --- | --- |
| Parse | Parse source and target bytes into Foundation values and `JSONElement` wrappers. |
| Generate | Construct a patch from prepared source and target elements, including any per-call caches or indexes. |
| Serialize | Serialize a prepared patch with the documented writer options. |
| Apply | Apply a prepared patch to a fresh source document. Report in-place and `.applyOnCopy` separately. |
| Generate and serialize | Parse source and target bytes, generate a patch, and serialize it. |
| Complete round trip | Parse documents, generate and serialize a patch, decode the patch, apply it to a fresh source, and serialize the result. |

For generation-only timing, prepare inputs outside the timed interval. For in-place application, restore the source outside each timed invocation; never apply repeatedly to a previously patched document. The `.applyOnCopy` measurement includes the copy performed by that API. Document whether destruction of returned objects is included, and keep that choice consistent across revisions. Include normal creation and destruction costs in the complete round trip.

Also record input sizes, node counts, maximum depth, serialized patch bytes, operation counts by type, and peak resident memory. Report memory from a fresh child process for each case and operation. State that process memory includes the runtime and fixture; do not describe peak RSS as an exact allocation count or subtract unrelated high-water marks. Normalize platform-specific memory units. Use Instruments or an allocation profiler for focused investigations when necessary.

Record raw patch size using the library's normal serialization options. Record compressed size as a secondary metric with a fixed compressor configuration, outside timing. Keep compression settings and tool versions in the result metadata. A byte-saving change may have different value for compressed transport and local application.

### Build a deterministic corpus

Use named cases with fixed seeds and checked-in or reproducibly generated input bytes. A case identifier includes its parameters, seed, and fixture version. Record fixture hashes. Produce identical fixture bytes on Darwin and Linux; generate documents with distinct Unicode property spellings directly as JSON, rather than through a Swift dictionary that could merge keys.

Cover these workload families:

| Family | Cases and purpose |
| --- | --- |
| Unchanged documents | Same reference, separately parsed equal documents, and equal nested containers. Distinguish identity shortcuts from structural equality. |
| Sparse changes | One leaf replacement in wide objects, deep objects, and arrays; changes near the beginning and end. Expose repeated traversal and comparison. |
| Object churn | Additions, removals, renames, and mixed edits, at low and high change densities. |
| Copy candidates | Few and many unchanged candidates; successful and unsuccessful searches; repeated strings, numbers, arrays, and objects. Vary value size and repetition. |
| Encoding tradeoffs | Tiny values with long source paths, large values with short paths, escaped paths, and many equivalent candidates. Measure when `copy` helps. |
| Array edits | Append, prepend, middle insertion/deletion, replacement, rotation, reversal, and mixed edits. Include duplicate values and objects with similar contents. |
| Dense changes | Mostly unrelated documents and root type changes. Measure when a detailed diff becomes more expensive than subtree replacement. |
| Existing fixtures | Retain `bigexample1.json` and `bigexample2.json` as one named fixture pair with recorded hashes. They are not the whole workload model. |
| Semantic boundaries | Null, Boolean versus number, integer precision boundaries, empty keys, `/` and `~` in keys, composed/decomposed Unicode, and nested mutable containers. |

Start with small, medium, and large sizes, such as 10, 1,000, and 10,000 entries. Define depth and value-byte limits separately. Use a curated quick subset and a fuller matrix; do not multiply every size, mutation rate, value type, and mutability setting into an unbounded suite.

Use immutable parsed documents for the primary timing matrix. Add selected mutable/mixed Foundation cases and run the full mutability matrix for correctness. Do not assume a macOS improvement also benefits corelibs Foundation on Linux.

### Validate every measured case

Before accepting timings, verify that generating, serializing, decoding, and applying the patch produces the target. Validate again after measurement to catch accidental input mutation or patch reuse errors. Consume measured results through a checksum so the compiler cannot discard the work; keep full validation outside timed intervals.

Use an independent recursive JSON comparator in the benchmark support code. It must compare keys and strings by Unicode scalar spelling, distinguish Boolean values from numeric values, and preserve integer precision. Test the comparator against known unequal boundary values. Do not rely solely on the generator's own equality helper or compare serialized object key order.

Validate that source and target inputs remain unchanged by generation and that a generated patch can be reused on independent source documents. When the harness finds a library defect, add a small regression test to the ordinary test suite and resolve or explicitly record that defect before interpreting its timing. A failed case is not a fast result.

Do not require one exact operation sequence where several valid patches exist. Use exact expectations only for a focused contract or algorithm test, such as producing one insertion for a simple array prepend.

### Make measurements reproducible

Build in Release with the same compiler options for baseline and candidate. Record the commit and dirty state, Swift and Xcode versions, OS, architecture, CPU, build flags, harness version, fixture hashes, and measurement settings. Record the library revision separately from the harness revision so the same harness can compare two checkouts.

Use a monotonic clock. Warm up each case, calibrate iterations to exceed timer overhead, and collect multiple samples in independent processes. Bound calibration so a slow case cannot make the suite run indefinitely. Report the median and spread of per-operation batch times, raw sample counts, and independent process results. Do not present a percentile of batch averages as a request-latency percentile.

For a candidate comparison, alternate baseline and candidate processes on the same idle machine and toolchain. Use at least three independent process pairs for a decision. Repeat unchanged-baseline comparisons first to establish measurement noise. Do not claim an improvement smaller than that noise, and do not compare absolute timings across different machines or operating systems.

Set case timeouts and memory limits before running candidates. Report a limit breach explicitly, with the case and limit; never silently omit it from the comparison. Investigate unexpectedly broad variance before drawing conclusions.

### Add continuous integration without noisy timing gates

Add a benchmark smoke job on macOS and Linux using the repository's existing supported toolchains. It builds the harness, validates the quick corpus, checks the result schema, and uploads results. Shared hosted-runner timings are informational initially.

Run the full matrix manually or through a manually triggered workflow, retaining raw results and comparison reports as artifacts. Use a consistent machine for performance decisions. Introduce timing thresholds only after repeated baseline runs establish useful limits. Keep correctness and harness failures blocking from the start.

**Stage completion:** another developer can reproduce a result from documented commands, compare two revisions using the same harness, and explain every measured boundary. The baseline report contains per-family results for Darwin and Linux, a measured noise range, known limitations, and the next cost to investigate. No generator algorithm changes are included in this stage.

## 2. Reduce repeated traversal and comparison

Profile representative sparse, unchanged, deeply nested, and large-fixture cases from the baseline. Identify time spent in equality, key-set construction, Foundation bridging, pointer construction, and candidate collection.

Evaluate a traversal that discovers differences and stable copy sources together, followed by an encoding pass over the planned operations. Preserve operation order. Investigate reusing key sets and comparisons within one generation call before introducing an entirely new document representation.

Keep any cache local to one call because `JSONElement` can retain mutable Foundation objects. Avoid a full indexing or normalization pass when its cost exceeds the work saved on small documents.

Add focused correctness tests for paths discovered before and after an addition and for nested arrays. Run the ordinary Debug and Release tests on macOS and Linux, then the same benchmark matrix against the fixed baseline.

**Stage completion:** measured traversal savings exceed baseline noise on the target cases, and the report accounts for small-document overhead, memory, output sizes, and application cost. Defer representation changes that lack a measured benefit.

## 3. Improve copy lookup and encoding choices

Measure candidate count, additions, hit rate, value type, and value size in diagnostic runs. Compare linear search with a lazily built index. Include index construction in generation time. Use a small candidate set without an index when that measures better.

Start with a limited value type if useful, then evaluate structural fingerprints for containers. Equal values must reach the same bucket under the library's JSON equality rules, and a hash match must still receive an exact equality check. Add collision tests and numeric/Unicode boundary tests before extending the index. Avoid JSON serialization as an unmeasured shortcut for hashing or equality.

Choose `copy` only when it benefits the selected cost policy. Begin with serialized operation size: include escaped source and destination paths, operation metadata, and the literal value. Evaluate the cost of estimating size so the optimizer does not spend more than it saves. Prefer a stable, short source path among equivalent safe candidates.

A copy source must exist and still contain the expected value when that operation executes. Preserve that invariant explicitly; a value unchanged between the initial and final documents is not sufficient for arbitrary reordered operations.

**Stage completion:** candidate-heavy cases improve without losing large-value reuse, tiny values avoid unnecessarily larger copies, and collisions cannot change correctness. Publish timing, size, memory, and application results, including any regressions accepted as a tradeoff.

## 4. Improve array edit quality with bounded work

Begin with common-prefix and common-suffix matching for straightforward insertions and deletions. Then compare the existing positional strategy with a sequence-diff strategy for the remaining region. Use exact JSON equality and include duplicate-heavy, reversed, and unrelated arrays.

Bound the work or memory used by expensive matching, with a deterministic fallback to positional edits or subtree replacement. Swift's collection-difference algorithm is one candidate to evaluate, not an automatic choice: its documented worst case is quadratic. Measure its comparison cost for nested JSON values.

Apply removals and insertions in an order that preserves sequential JSON Patch indices. Reassess copy-source paths when array indices shift. Keep automatic move generation deferred until its index and source-validity rules have dedicated tests and a measured advantage; retain the v2.0.0 array-transfer regressions.

**Stage completion:** prepend and middle-insertion cases produce substantially smaller patches, all round trips remain correct, and unrelated or adversarial arrays stay within the declared work and memory bounds. Demonstrate effects on application time as well as generation time.

## 5. Evaluate adaptive strategies and public options

With the earlier stages measured, investigate choosing between a detailed diff and replacing a changed subtree. Use deterministic work limits and cost estimates. Benchmark sparse and dense changes, small values, and large repeated containers; include estimation overhead.

Only introduce a public generation option if results establish a recurring tradeoff that one default cannot serve well. Keep existing call sites source-compatible and document the behavior of any option. Review consumers' possible dependence on operation order, exact patch bytes, or operation types even when the resulting document is unchanged. Decide the release and documentation implications explicitly.

Use per-family comparisons rather than one aggregate score to accept changes. Require correctness, repeatable gains above noise, and an explanation for any output-size, application-time, or memory regression. Retain an implementation only when its measured benefit justifies its complexity.

## Delivery order

| Change | Deliverable | Evidence required before proceeding |
| --- | --- | --- |
| 1 | Benchmark package, corpus, comparator, scripts, documentation, and CI smoke jobs | Reproducible v2.0.0 baseline and baseline-versus-baseline noise measurements. |
| 2 | Shared traversal and limited per-call reuse | Profiling evidence and a full comparison report. |
| 3 | Copy lookup and size-aware encoding | Candidate-search gains, collision coverage, and size/application tradeoffs. |
| 4 | Bounded array matching | Smaller insertion/deletion patches and bounded difficult cases. |
| 5 | Adaptive strategies or public options, if justified | A documented use case that the improved default cannot serve adequately. |

Each algorithm change includes focused regression tests, the existing correctness checks, and a report produced by the same benchmark harness. Run the existing Apple distribution checks before releasing changes that affect package layout, supported platforms, or distributed sources.

## References

- [RFC 6902](https://www.rfc-editor.org/rfc/rfc6902.html) defines sequential patch application, copy-source requirements, and JSON equality.
- [Swift collection diffing](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/Diffing.swift) provides a sequence-diff implementation and documents its worst-case complexity. Pin the inspected revision if it becomes an experimental dependency or comparison reference.
- [Swift 6 migration guidance](Swift6Migration.md) documents the library's value-transfer and compatibility boundaries.
