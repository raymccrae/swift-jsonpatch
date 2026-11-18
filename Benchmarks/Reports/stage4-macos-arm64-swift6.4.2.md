# Stage 4: bounded array edit quality

Retain the local stage 4 implementation. Straightforward array insertions and deletions become single edits, and short rotations retain the shared sequence. Search work is capped, with recursive positional edits as the fallback. The tradeoff is extra matching work on some small or difficult arrays and limited quality improvements for large nested values. The public API is unchanged; automatic moves and adaptive subtree replacement remain deferred.

The primary comparison is stage 3, commit `15818c6cb3dff44402a5f200907daa0f9f734814`. A supplementary generation comparison uses v2.0.0, commit `7ccc425d3e58da374c9af600074c6ff223089fe8`. The [machine-readable report](stage4-macos-arm64-swift6.4.2.json) retains every paired row, process medians/sample ranges, sizes, operation counts, memory observations, reproduction metadata, and untimed array diagnostics. Work remains local on `feature/patch-generation`; neither `develop` nor `master` is changed.

## Implementation and bounds

The [generator](../../Sources/JSONPatch/JSONPatchGenerator.swift) first finds an exactly equal prefix and suffix. It searches the remaining middle with Myers's sequence algorithm, bounded to an insertion/deletion distance of `min(8, max(2, (sourceMiddleCount + targetMiddleCount) / 4))`. A one-element substitution needs no sequence search. Singleton array pairs recurse directly, avoiding repeated structural probes through deep singleton chains.

The matcher shares a budget of **65,536 weighted work units per array search**, including the affix scans. Node comparisons and frontier steps spend units; container counts and string/key UTF-16 lengths are precharged before structural comparison. Strings and property names use exact Unicode scalar identity, Boolean values remain distinct from numbers, and numeric equality uses the existing library semantics. Matching equality stops at container depth 16 or objects with more than 32 fields. Object keys are visited in scalar order; the canonical first key is probed before sorting the remainder so cheap mismatches can stop early. Reference identity is a safe shortcut within a generation call.

An exhausted work/depth/shape budget or distance limit retains the proven affixes and uses positional comparison for the unmatched region. It also disables further sequence searches within that region's descendants, preventing a failed outer search from restarting at every nested array. This is an extra-search budget, not a bound on necessary document traversal, Foundation allocations, copy lookup, or the total time of a generation call. A document with independent edited arrays can perform more than one bounded search.

At distance eight, the backtracking trace stores at most **171 integers**, plus a 19-integer frontier: 1,520 bytes of integer payload on this 64-bit host, before Swift container overhead. Retained matching anchors and the resulting comparison plan can still occupy O(n) storage. The implementation does not construct a quadratic LCS matrix or call an unbounded collection-difference routine.

Matched runs retain their elements. Unmatched runs pair recursive substitutions first, remove excess elements in descending current-index order, then insert excess elements at ascending target indices. End insertions keep the `-` path. An alignment is rejected if its coalesced top-level edits exceed a positional middle's operation-count ceiling; this prevents small reversals from becoming many removals and additions. This is a local heuristic, not a guarantee of globally minimal operation count or serialized bytes for nested JSON.

Copy resolution still replaces additions in place. Only unchanged sources before the first array-index shift, together with unchanged sources outside that edited array, participate. All shifted suffix positions are excluded, even if a later edit restores their original index. Nested changes inherit that restriction. This conservative policy preserves source validity throughout the sequential patch and retains useful safe-prefix copies; it can forgo copies available under more elaborate scheduling.

## Measurements

Measurements use an Apple M5 Pro, macOS 27.0.1, Xcode 27.2, and Apple Swift 6.4.2. Both libraries use the same Release harness, corpus, compiler flags, and settings. The measured candidate is a dirty working tree based on stage 3; its source/package content SHA-256 is `7ea79ccfa1c0f164afe91d1703b60d9e809e5d3fe40a8effef13c71343496bea`. That hash matches the library accompanying this report.

Corpus version 3 has 29 quick and 81 full cases. New cases cover sparse multiple insertions, duplicates, unrelated arrays, nested records, large equal arrays, safe/shifted donors, exact matching semantics, and deep singleton chains. Existing input bytes are unchanged, but versioned IDs and the harness hash change. Historical v1/v2 reports must not be directly compared with this capture.

All **370 paired rows** passed: 29 stage-3-versus-stage-3 generation noise cases, 203 quick case/measurement combinations against stage 3, 81 full generation cases, 28 large-array combinations across all seven measurements, and 29 quick generation comparisons against v2.0.0. Each row has three alternating process pairs and separate memory workers. There were no timeouts or RSS-limit breaches. Full generation includes size and memory observations; application/round-trip timings cover the quick corpus and the four selected 10,000-element array cases, rather than every full case.

Times below are milliseconds, summarized as the median of process medians. Ratios summarize paired candidate/baseline ratios, so they need not equal the quotient of displayed times. Ranges describe observed process variation, not confidence intervals or request-latency percentiles.

### Patch quality and generation

| Array case | Operations, stage 3 → 4 | Raw bytes, stage 3 → 4 | Generation ms, stage 3 → 4 | Paired ratio (range) |
| --- | ---: | ---: | ---: | ---: |
| Prepend, 1,000 numbers | 1,001 → 1 | 43,818 → 38 | 1.678 → 1.551 | 0.918 (0.890–0.985) |
| Middle insertion, 1,000 | 501 → 1 | 22,038 → 40 | 1.556 → 1.502 | 0.969 (0.896–0.973) |
| Middle deletion, 1,000 | 500 → 1 | 21,988 → 32 | 1.619 → 1.522 | 0.961 (0.935–0.976) |
| Rotation, 1,000 | 1,000 → 2 | 43,781 → 66 | 1.670 → 1.532 | 0.909 (0.909–0.967) |
| Duplicate-heavy rotation, 1,000 | 1,000 → 2 | 41,891 → 66 | 1.618 → 1.590 | 0.982 (0.914–1.013) |
| Two separated insertions, 1,000 | 752 → 2 | 33,075 → 79 | 1.684 → 1.640 | 0.985 (0.972–1.073) |
| Prepend, 100 nested records | 202 → 1 | 11,058 → 334 | 1.247 → 1.029 | 0.822 (0.810–0.835) |

The patch-shape changes are substantial. Generation still needs to inspect the shared sequence, so generation savings are much smaller; the duplicate and two-insertion timings do not establish a speedup above noise. For the 1,000-number prepend, gzip shrinks from 5,141 to 55 bytes. The nested-record prepend shrinks from a median 1,131 to 94 gzip bytes in the generation row; object operation order can change compression across processes and measurements.

The 1,000-record prepend reaches the equality budget. Its patch improves only from 2,002 to 1,766 operations and 110,058 to 97,080 bytes, with generation 12.673 → 12.255 ms (paired ratio 0.964, range 0.949–1.018). It does not become a single insertion. Retaining the fixed cap is preferable here to an input-size-dependent structural search, but larger-record quality remains a limitation.

### Application and complete round trips

| Array case | In-place application ms, stage 3 → 4 | Apply-on-copy ms, stage 3 → 4 | Complete round trip ms, stage 3 → 4 |
| --- | ---: | ---: | ---: |
| Prepend, 1,000 | 1.937 → 0.00188 | 2.499 → 0.460 | 6.278 → 1.648 |
| Middle insertion, 1,000 | 0.985 → 0.00192 | 1.427 → 0.463 | 3.855 → 1.672 |
| Middle deletion, 1,000 | 0.986 → 0.00075 | 1.493 → 0.477 | 3.935 → 1.722 |
| Rotation, 1,000 | 2.087 → 0.00195 | 2.530 → 0.458 | 6.410 → 1.674 |
| Two separated insertions, 1,000 | 1.496 → 0.00334 | 2.076 → 0.479 | 5.097 → 1.666 |
| Prepend, 100 records | 0.417 → 0.00339 | 0.707 → 0.270 | 2.551 → 1.313 |

The 1,000-number prepend's paired round-trip ratios span 0.262–0.273, and its apply-on-copy ratios span 0.183–0.197. Copying the source remains part of apply-on-copy; restoring a fresh mutable input remains outside the in-place interval. Single-operation application timings are sensitive to wrapper/timer overhead. Some tiny cases reach the 10,000-iteration calibration cap before accumulating the 10 ms target; the flags and actual sample ranges remain in the JSON. The large reduction from hundreds or thousands of operations is clear without treating sub-microsecond timings as precise latency promises.

Selected large-array results confirm that the benefit persists at 10,000 elements:

| Case | Raw patch bytes, stage 3 → 4 | Generation ms | Apply-on-copy ms | Complete round trip ms |
| --- | ---: | ---: | ---: | ---: |
| Prepend | 457,818 → 38 | 15.770 → 14.784 | 24.429 → 4.537 | 65.067 → 16.544 |
| Middle insertion | 230,038 → 41 | 15.569 → 15.322 | 14.673 → 4.521 | 39.148 → 16.603 |
| Middle deletion | 229,987 → 33 | 15.607 → 14.864 | 14.480 → 4.598 | 38.997 → 16.403 |
| Reversal | 457,781 → 457,781 | 16.405 → 16.185 | 24.684 → 24.330 | 61.641 → 61.884 |

The reversal intentionally keeps 10,000 positional replacements. Its generation ratio is 0.993 (0.985–0.999), and round-trip ratio 1.004 (1.003–1.005): no material reversal improvement is claimed. In-place application of the prepend falls from 20.774 to 0.00188 ms; its apply-on-copy and round-trip changes provide less overhead-sensitive evidence.

### Accepted costs, noise, and memory

Failed searches still cost work. These full-generation rows expose the principal regressions; their raw patch sizes are unchanged:

| Case | Stage 3 ms | Stage 4 ms | Paired ratio (range) |
| --- | ---: | ---: | ---: |
| Matching semantic boundaries | 0.00502 | 0.01874 | 3.758 (3.722–3.812) |
| Integer-boundary array | 0.00546 | 0.01882 | 3.468 (3.433–3.587) |
| Ten-element reversal | 0.01724 | 0.05322 | 3.086 (3.049–3.114) |
| Nested array transfer | 0.00720 | 0.01230 | 1.695 (1.667–1.901) |
| Shifted-donor prepend with a large string | 0.00899 | 0.01424 | 1.590 (1.547–1.610) |
| Reversal, 1,000 | 1.656 | 1.762 | 1.049 (1.022–1.095) |
| Unrelated array, 1,000 | 1.624 | 1.705 | 1.047 (1.014–1.071) |
| Repository fixture | 6.690 | 6.939 | 1.022 (1.012–1.041) |

Small mutable-container fixtures rise from about 0.0093–0.0099 to 0.0136–0.0150 ms, also without patch changes. A ten-element rotation improves from ten operations/401 bytes to two/66 bytes, but generation rises 0.01747 → 0.02384 ms (ratio 1.330). The safe-prefix donor fixture retains its copy and unchanged patch bytes, with generation 0.1547 → 0.1657 ms. These are accepted costs of bounded sequence discovery and exact structural matching. A later policy could revisit small-array search thresholds if a real workload justifies sacrificing short-sequence quality; this stage adds no public tuning option.

The fresh identical-library capture has median absolute paired deviation **1.73%**, a maximum 44.95% deviation in the object-hit copy case, and one 23.34% deviation in the string-hit case. Other noise cases have a maximum 9.05% deviation. Stage 3's [controlled equality-order investigation](stage3-macos-arm64-swift6.4.2.md#investigating-the-object-case-variance) already establishes substantial hash-order sensitivity for failed object copy comparisons. No copy-lookup or tiny timing improvement is inferred from these noisy rows. Compare relevant case ranges; the maximum is not a universal acceptance threshold. The large size/application gains and repeated small semantic/reversal regressions exceed their own observed variation.

No median raw patch size increases in the captured comparisons. Gzip changes range from −5,086 to +71 bytes in quick measurements and −49,778 to +11 bytes in full generation. Unchanged raw sizes can compress differently because independent object operations may be ordered differently.

Quick dedicated-worker peak-RSS differences range from −0.86 to +0.14 MiB; full-generation differences from −2.17 to +0.20 MiB; selected large-array differences from −3.75 to +0.22 MiB. The largest candidate full-generation process peak is 14.44 MiB. These include the runtime, prepared inputs, and mode-specific prepared patch, rather than exact library allocations or worst-case guarantees. Compact plans/patches reduce observed peaks in some cases; the fixed trace payload alone does not bound total memory.

The same v3 harness against v2.0.0 shows generation 3.268 → 1.540 ms for the 1,000-number prepend, 55.545 → 3.245 ms for the 1,000-source copy miss case, and 16.743 → 7.321 ms for the repository fixture. These cumulative gains include stages 2 and 3. The primary stage-3 comparison above isolates the array work.


## Why these limits

An exploratory distance-32 prototype produced eighteen edits for a ten-element reversal and increased its raw patch by 185 bytes. It was rejected. A distance-eight cap, a tighter relative cap on small middles, and rejection of inflated edit sequences preserve positional reversal output. Early prototypes also restarted searches inside the unrelated repository fixture, adding about 60% to generation time. Propagating fallback through unmatched descendants and probing the canonical first object key removed most of that cost. Prototype timings are investigative observations; the final paired captures below are the acceptance evidence.

The fixed work cap deliberately limits improvements for large records. The 100-record prepend is fully matched within 55,242 units. The 1,000-record prepend consumes 65,117 units, retains only a proven suffix, and falls back for the rest; its descendants do not restart searches. A 10,000-element numeric rotation needs 10,009 units and 57 trace entries. The 1,000- and 10,000-element reversals, and the 1,000-element unrelated numeric array, stop after 92 units and 171 trace entries. Deep singleton chains perform no sequence search. These are observations from a temporary instrumented copy, not timing samples or library-wide allocation bounds.

Run the untimed diagnostics separately from benchmarks:

```sh
python3 Scripts/diagnose-patch-generation.py --include-arrays \
  --case arrays/ --case fixtures/ \
  --output Benchmarks/Results/stage4-diagnostics.json
```

The diagnostic tool compiles copied sources with counters and leaves the checkout unchanged. Diagnostic globals and logging are absent from the shipping and measured generator. The companion JSON records source and instrumentation hashes and per-array search, fallback, affix, anchor, work, and trace counts.

## Validation and reproduction

- All 124 ordinary tests pass in Debug and Release, with compiler warnings treated as errors.
- All 124 tests pass in the macOS Xcode target. The command-line `MACOSX_DEPLOYMENT_TARGET=14.0` override accommodates this host's test framework; library and project deployment settings are unchanged.
- All 324 full-corpus case/mutability combinations pass independent result comparison, serialization/application, input preservation, and patch reuse.
- All seven Swift benchmark-support tests and all 14 Python harness tests pass.
- New focused expectations cover single edits, edit-run indices, two-edit rotations, small-reversal operation counts, leaf substitutions, safe/shifted copy donors, exact JSON identity, and deep singleton arrays. All 225 pairs of binary arrays through length three round-trip across four mutability combinations; 3,969 pairs through length five check anchors against an independent LCS oracle when a search succeeds. Bounds are checked directly as well as through diagnostics.
- Linux and the supported Xcode 16.2/26.3 matrix remain pending while the branch stays local. This host has no Linux runtime. Cross-platform stage acceptance is not claimed.

Use the stage 4 commit introducing this report, or matching library/harness content hashes. Run these commands serially on the same idle machine. Each timed capture uses three alternating process pairs, five samples, a 10 ms calibration target, one warmup, a 180-second worker timeout, and a 1,024 MiB resident-memory ceiling. Polling is enabled. Results stay under the ignored local directory.

```sh
python3 Scripts/benchmark-patch-generation.py --profile full --validate-only \
  --output Benchmarks/Results/stage4-validation
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref 15818c6 --library-ref 15818c6 --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage4-noise-final
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref 15818c6 --mode all \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage4-quick
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref 15818c6 --profile full --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage4-full-generation
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref 15818c6 --profile full --mode all \
  --case arrays/prepend-n10000 --case arrays/insert-n10000 \
  --case arrays/delete-n10000 --case arrays/reverse-n10000 \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage4-large-arrays
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref v2.0.0 --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage4-release-generation
```
