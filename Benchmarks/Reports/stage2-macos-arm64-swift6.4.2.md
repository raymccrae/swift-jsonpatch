# Stage 2: share comparison and patch planning

Stage 2 replaces repeated structural comparisons with a per-call comparison plan. The public API, positional array edits, and linear copy lookup remain unchanged. This report assesses the local macOS implementation against v2.0.0 (`7ccc425d3e58da374c9af600074c6ff223089fe8`); Linux and the supported Xcode matrix remain pending while the feature branch stays local.

## Implementation and source validity

The [generator](../../Sources/JSONPatch/JSONPatchGenerator.swift) compares corresponding values once to discover both edits and unchanged subtrees. Object key sets and Foundation-to-`JSONElement` conversions serve that comparison instead of being repeated in an unchanged-value traversal and a difference traversal. Equal containers collapse into one unchanged source, retaining the release's copy-candidate policy. Identical container references can return immediately.

Planning constructs paths after comparison. If there are no additions, it skips unchanged-source collection and avoids constructing pointers for unchanged children. The planned operations use the public operation representation directly, without retaining unused old values or mapping a second operation buffer. The plan and source collection belong to one generation call; mutable input changes cannot invalidate a cache retained between calls.

Copy resolution runs after every stable source has been collected, including sources encountered after an addition. It replaces an `add` in place rather than moving operations. Objects retain the removal, addition, and common-property edit order. Arrays retain descending tail removals, edits at common indices, and tail appends. These edits cannot shift the paths of unchanged sources at common keys or indices. Reordered edits or future array matching must revisit that invariant.

This change does not index copy candidates, choose copies by encoded cost, generate moves, match array sequences, or introduce public generation options. Those remain later stages of the [plan](../../Docs/PatchGenerationPlan.md).

## Profiling

The release and candidate are sampled in separate diagnostic runs on four generation cases: separately parsed equal objects with 1,000 properties, a sparse change among 1,000 properties, depth 64, and the repository's large fixture. Each sampling session uses the Release benchmark worker, 1 ms sampling intervals, and a three-second capture. These diagnostic runs are separate from the paired timing runs.

The release stacks show repeated recursive equality beneath the unchanged-value and diff traversals, including repeated work along the deep case's ancestor chain. Foundation dynamic casts, protocol-conformance lookup, and key bridging appear prominently. Pointer construction also occurs in the unchanged-source pass. This supports sharing comparisons and avoiding unused paths before attempting a new document representation. Sampled stacks are diagnostic observations, not precise allocation counts or function-level speedup estimates.

Local stacks and fixture bytes are retained under `Benchmarks/Results/stage2-profiles/`. To reproduce a diagnostic capture, obtain a case's source and target bytes from `Scripts/patch_generation_benchmark.py`'s `corpus("full")`, launch the corresponding Release worker, and sample its PID:

```sh
PATH_TO_WORKER --source source.json --target target.json --mode generate \
  --samples 1000 --sample-ms 10 --max-iterations 10000
sample WORKER_PID 3 1 -mayDie -file generation.sample.txt
```

The long worker run keeps generation active during sampling; stop it after the capture. Use the `build-baseline` and `build-candidate` binaries produced by the paired runner. Do not run sampling alongside the timing measurements.

## Measurements

Retain this implementation: traversal-sensitive generation and round trips improve substantially on this machine, while useful copies and focused patch quality remain intact. Linear copy search remains a bottleneck for stage 3. The [machine-readable summary](stage2-macos-arm64-swift6.4.2.json) records all cases, process medians and sample ranges, paired ratios, operation counts, raw/gzip sizes, memory, and provenance.

The capture uses an Apple M5 Pro, macOS 27.0.1, Xcode 27.2, and Apple Swift 6.4.2. Both variants use the same Release harness and compiler flags. The measured candidate is a dirty working tree based on `ba9624c`; its library content SHA-256 is `6df91b45a728e440b068e106698dd7d626752c039c19e3e88a0b214eb489b393`. The source content matches the implementation accompanying this report. The summary records the parent revision separately from that content hash, plus a standalone generator hash.

The runs contain 18 generation-only release-versus-release noise cases, all 126 quick-corpus case/measurement combinations, and all 59 full-corpus generation cases. Each has three alternating process pairs and separate memory workers. There are no failed rows, timeouts, or memory-limit breaches. All seven measurements cover the quick corpus; full-corpus serialization, application, and round-trip timings were not captured. Full-corpus generation includes validated serialized round trips and patch-size/memory measurements.

Times below are milliseconds, summarized as the median of process medians. Ratios are the median of the three paired candidate/baseline ratios; they need not equal the quotient of the displayed times. Ranges describe observed process-pair variation, not confidence intervals or request-latency percentiles.

| Capture | Generation case | Release ms | Candidate ms | Paired ratio | Pair range |
| --- | --- | ---: | ---: | ---: | ---: |
| Quick | Separately parsed equal object, 10 properties | 0.0379 | 0.0197 | 0.512 | 0.511–0.529 |
| Quick | One replacement among 1,000 properties | 5.742 | 1.909 | 0.332 | 0.278–0.369 |
| Quick | Depth 8 | 0.605 | 0.063 | 0.103 | 0.096–0.120 |
| Quick | Repository large fixture | 18.206 | 6.773 | 0.372 | 0.366–0.399 |
| Quick | Prepend to 1,000 elements | 3.334 | 1.681 | 0.505 | 0.494–0.507 |
| Quick | Thirty copies of a 10 KB string | 3.356 | 3.233 | 0.963 | 0.958–1.019 |
| Full | Separately parsed equal object, 10,000 properties | 38.572 | 20.653 | 0.529 | 0.515–0.559 |
| Full | One replacement among 10,000 properties, last key | 60.784 | 20.112 | 0.323 | 0.300–0.355 |
| Full | Depth 64 | 20.759 | 0.488 | 0.023 | 0.019–0.029 |
| Full | Append to 10,000 elements | 35.647 | 18.654 | 0.528 | 0.521–0.531 |
| Full | 3,000 unsuccessful copy searches among 10,000 sources | 5,233.653 | 5,225.907 | 0.994 | 0.989–1.010 |

The fresh release-versus-release generation run observes a median absolute pair deviation of 1.8%, with a maximum of 20.1%. The large traversal reductions exceed that observed noise. Small differences in copy-heavy cases do not establish a copy-search improvement. Noise was sampled on quick-corpus generation, not every full case or measurement. Very small root-only cases and the same-reference identity shortcut reach the iteration cap; their absolute timings are sensitive to clock and wrapper overhead.

The quick corpus also shows benefits after serialization and application are included:

| Complete round trip | Release ms | Candidate ms | Paired ratio | Pair range |
| --- | ---: | ---: | ---: | ---: |
| One replacement among 1,000 properties | 7.737 | 2.495 | 0.326 | 0.296–0.336 |
| Repository large fixture | 33.988 | 23.150 | 0.688 | 0.661–0.698 |
| Prepend to 1,000 elements | 7.994 | 6.312 | 0.795 | 0.790–0.800 |

There is no observed material application-cost or small-document regression in these runs. Across quick cases, median paired ratios range from 0.972 to 1.034 for in-place application and 0.980 to 1.039 for application on a copy. Parse and serialize measurements also remain close to the release. These paths were not optimized, so interpret small differences as variation rather than improvements.

### Patch quality and memory

Operation counts match the release in every measured case. Median raw patch sizes also match throughout both candidate captures. The full corpus's equivalent-donor case produces 46 or 47 bytes depending on the randomly selected source path; the release samples here are 47 bytes. Independent object-operation ordering and equivalent donor selection remain unspecified. Gzip median deltas vary from −157 to +88 bytes across quick rows and −28 to +48 bytes across full-generation rows. No compression or encoding policy changed.

The temporary comparison plan has a measured memory tradeoff. Full-generation peak-RSS differences range from about −1.98 MiB to +0.41 MiB. The largest increase occurs for the 10,000-element append; separately parsed equal 10,000-property objects increase about 0.16 MiB. Sparse 10,000-property replacements decrease about 1.95–1.98 MiB, consistent with skipping unnecessary source collection and paths. The largest candidate full-generation peak is 13.6 MiB. These are differences between dedicated workers' maximum process peaks, including runtime and prepared inputs, not allocation attribution or a library-only memory bound.

The retained design trades some temporary comparison storage for fewer Foundation conversions, key sets, equality walks, and paths. These local results justify that tradeoff. Candidate indexing and array matching still require their own measurements and quality expectations.

## Validation

- All 102 ordinary tests pass in Debug and Release with compiler warnings treated as errors, including 128 seeded document pairs and the focused quality checks.
- All 102 tests pass in the standalone macOS Xcode target. Xcode 27.2 requires a command-line `MACOSX_DEPLOYMENT_TARGET=14.0` override to build the project's older deployment target; the project and library deployment settings are unchanged.
- All 236 full-corpus source/target mutability combinations pass independent result comparison, serialization, reuse, and input-preservation checks.
- All seven Swift benchmark-support tests and all 12 Python harness regression tests pass.
- Two additional focused regressions check copying an unchanged child of a changing ancestor, with the donor before and after the addition, and shared mutable arrays/objects edited between generation calls. Both pass against the exported original release and the candidate.

Application checks use the library's interpreter with an independent result comparator. These checks are not a second implementation of patch application or exhaustive testing.

## Reproduce the comparisons

Run the following commands serially on the same idle machine. Each command alternates three independent baseline/candidate process pairs, captures five samples per process with a 10 ms calibration target and one warmup, and measures memory in separate workers. The per-worker timeout is 180 seconds and the RSS limit is 1,024 MiB. Resident-memory polling is enabled for the reported runs.

```sh
python3 Scripts/benchmark-patch-generation.py \
  --library-ref v2.0.0 --baseline-ref v2.0.0 --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage2-noise-final
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref v2.0.0 --profile quick --mode all \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage2-quick
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref v2.0.0 --profile full --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage2-full-generation
```

Full timing samples remain ignored under `Benchmarks/Results/`; the compact summary retains the measured source and harness hashes, settings, fixture metadata, process medians, paired ratios, sizes, operation counts, and memory measurements. Per-process arrays follow each row's `process_pair_ids`. Re-run against the commit introducing this report, or a checkout whose library and harness content match the recorded hashes, rather than comparing absolute times from another machine.
