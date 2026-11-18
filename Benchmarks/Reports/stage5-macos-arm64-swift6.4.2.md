# Stage 5: adaptive generation and public options

Retain adaptive replacement for containers whose plans consist entirely of at least two direct replacements. This removes repeated operation/path metadata while carrying each target value once. Partial edits, unchanged copy sources, additions, removals, and array shifts retain the earlier strategies. The opt-in `JSONPatch.GenerationOption.preferSmallerPatch` performs additional bounded size estimates when callers prefer bytes/application cost over generation throughput.

The primary comparison is stage 4, commit `d73c5f216a25618e9767ddd6f6b69eea18decd9c`. The [machine-readable assessment](stage5-macos-arm64-swift6.4.2.json) records the retained implementation separately from exploratory variants, with library/harness hashes, settings, every paired row, process/sample summaries, sizes, operation counts, and dedicated memory measurements. The work remains local on `feature/patch-generation`.

## Selected policy and work bound

The [generator](../../Sources/JSONPatch/JSONPatchGenerator.swift) examines its existing comparison plan. An object qualifies when its keys are unchanged and every child is a replacement. An array qualifies when every part replaces the same original/target index; a retained run, insertion, removal, or shifted pair rejects it. At least two replacements are required. Decisions are bottom-up, so a completely changed nested container can coalesce before its parent is considered.

This is a structural cost proof, rather than another literal-size traversal. The detailed and replacement encodings contain each target value once. Their value sizes cancel, including large strings, nested containers, typed numbers, and escaped strings. For objects, quoted keys move from child pointers into the literal object; JSON Pointer escaping cannot make those keys cheaper than their literal spelling. Repeated `replace` metadata, parent paths, and child pointers cost more than the container syntax for two or more children. Tests compare the resulting patch against an explicitly constructed detailed patch with escaped/Unicode keys and repeated nested values.

The adaptation makes at most one short-circuiting shape pass over each existing direct-child plan. It performs no additional JSON equality, value traversal, serialization, numeric formatting, or subtree copying during generation. Its extra work is linear in the already constructed plan, and it requires no size cache or new document index. Stage 4's sequence-search limits remain unchanged. This does not bound the complete generation call's time or memory independently of input size.

No planned unchanged source is removed by coalescing: every eligible child was already a replacement. No planned addition can later become a smaller `copy` within that subtree. Sources outside it remain valid, and earlier array-shift restrictions still apply. The rule deliberately leaves a 99%-changed object detailed if it retains an unchanged child; it does not spend work estimating whether copying that retained value again would be worthwhile.

The optional policy runs after structural adaptation and copy resolution. It estimates each operation directly from its metadata, quoted paths, and literal values, without allocating a JSON dictionary for every operation. If the complete prepared patch fits the estimate limits, it compares its size with one root replacement. A tie, unsupported estimate, excessive depth, or exceeded budget retains the prepared patch.

Estimation runs for patches with two to 2,048 operations. The other limits are 65,536 estimated patch bytes, 16 value-container levels, and 32 pointer components. The replacement estimate saturates below the prepared patch size. Large strings and key sets receive cheap length checks before bounded bridging/traversal. Floating/decimal formatting still uses Foundation. These caps bound extra estimation shapes and encoded-byte scans; they are not instruction-count, allocation, or whole-call time guarantees. No configurable budget or optimization mode beyond this one option is exposed.

## Measurements

Measurements use an Apple M5 Pro, macOS 27.0.1, Xcode 27.2, and Apple Swift 6.4.2. The retained library's source/package SHA-256 is `7af1f73ebc3eea63a81ee4ebdf1ff03e4c0ab41d84df8c3cc598b423c2831f88`; it matches the accompanying code. The option adapter has a distinct recorded hash. All comparisons use the same v4 harness and machine on both sides.

All **856 standard paired rows** passed: 36 stage-4 noise cases, 36 current-default noise cases, 252 quick case/measurement combinations against stage 4, 94 full-generation cases, 28 large-array combinations, 36 quick generation comparisons against v2.0.0, 252 public-option quick combinations, 94 public-option full-generation cases, and 28 targeted option combinations. Three exploratory comparisons add **203 paired rows**, also all passing. There were no timeouts or RSS-limit breaches. Full generation records size/memory and correctness round trips; timed application/round-trip coverage is the quick corpus plus the selected large/targeted cases, rather than every full case.

Times below are milliseconds, summarized as the median of process medians. Ratios use medians of paired ratios, which need not equal the quotient of displayed times. Ranges describe process variation, not confidence intervals or request-latency percentiles.

### Adaptive default against stage 4

| Case | Operations, stage 4 → 5 | Raw bytes, stage 4 → 5 | Generation ms, stage 4 → 5 |
| --- | ---: | ---: | ---: |
| Complete object, 32 fields | 32 → 1 | 1,473 → 422 | 0.0648 → 0.0612 |
| Complete object, 1,000 fields | 1,000 → 1 | 48,001 → 14,038 | 2.070 → 1.925 |
| Unrelated array, 1,000 numbers | 1,000 → 1 | 44,784 → 4,931 | 1.727 → 1.654 |
| Sixty-four changed 4 KB strings | 64 → 1 | 265,335 → 263,196 | 0.1240 → 0.1181 |
| Thirty-two repeated target containers | 32 → 1 | 40,535 → 39,334 | 0.0825 → 0.0796 |
| Nested reversal beside unchanged payload | 64 → 1 | 3,181 → 228 | 1.250 → 1.232 |
| Repository fixture | 2,625 → 2,097 | 206,235 → 180,851 | 7.145 → 7.070 |

| Case | In-place application ms, stage 4 → 5 | Apply-on-copy ms | Complete round trip ms |
| --- | ---: | ---: | ---: |
| Complete object, 1,000 | 1.936 → 0.613 | 2.513 → 1.182 | 6.917 → 2.996 |
| Unrelated array, 1,000 | 2.048 → 0.463 | 2.441 → 0.944 | 6.357 → 2.337 |
| Sixty-four changed 4 KB strings | 0.109 → 0.044 | 0.153 → 0.090 | 1.984 → 1.759 |
| Repeated target containers | 1.016 → 1.002 | 1.030 → 1.001 | 1.633 → 1.567 |
| Nested reversal beside payload | 0.154 → 0.031 | 0.190 → 0.065 | 2.065 → 1.702 |
| Repository fixture | 5.295 → 4.353 | 7.373 → 6.540 | 23.580 → 20.808 |

The 1,000-field object's round-trip ratio is 0.435. The repository fixture's ratio is 0.883; its generation ratio of 0.990 does not establish a material traversal speedup. Reducing operation count is most valuable when metadata/path work dominates. For repeated containers, copying target values still costs about one millisecond, so removing 31 operations gives much less application benefit.

A 10,000-number reversal drops from 10,000 operations/457,781 bytes to one/48,928 bytes. Generation changes 16.765 → 15.881 ms, in-place application 20.769 → 4.715 ms, apply-on-copy 25.087 → 9.404 ms, and round trip 64.542 → 23.124 ms (paired ratio 0.359, range 0.356–0.362). The 10,000-field complete object drops from 490,001 to 150,038 bytes with generation 20.255 → 19.373 ms. The structural proof needs no byte scan even when the resulting literal exceeds the optional estimator's cap.

Stage 4's compact insertions/deletions remain compact. The 10,000-element prepend retains one operation and 38 bytes; its round trip is 17.187 → 17.208 ms, with no material change. A ten-element reversal shrinks from 401 to 58 bytes, but generation remains about 0.053 ms because its bounded sequence search still runs before adaptation.

No universal generation speedup is claimed. The largest non-tiny median full-generation increase is the indexed string-hit case, 0.4836 → 0.4944 ms (paired ratio 1.022, range 1.009–1.029). The remaining small movements and full process ranges are retained in the JSON. Size/application gains, rather than an aggregate timing score, justify the default rule.

### Public option against the adaptive default

For 1,000-field objects, the policy trades generation time for raw bytes and application work:

| Changed fields | Raw bytes, default → option | Generation ms | Apply-on-copy ms | Complete round trip ms |
| --- | ---: | ---: | ---: | ---: |
| 10% | 4,801 → 4,801 | 1.920 → 1.932 | 0.789 → 0.781 | 2.626 → 2.632 |
| 50% | 24,001 → 13,538 | 1.926 → 2.884 | 1.546 → 1.184 | 4.451 → 3.981 |
| 90% | 43,201 → 13,938 | 2.037 → 3.035 | 2.398 → 1.195 | 6.563 → 4.257 |
| 99% | 47,521 → 14,028 | 2.001 → 2.957 | 2.509 → 1.202 | 6.787 → 4.093 |

At 90%, generation ratios span 1.478–1.503 while round-trip ratios span 0.629–0.660. At 50%, generation ratios span 1.498–1.520 and round-trip ratios 0.886–0.894. At 99%, the corresponding ranges are 1.453–1.500 and 0.582–0.612. These repeated costs and benefits exceed their observed pair variation. The 10% case keeps the detailed patch; no material gain is claimed.

The option preserves the 81-byte two-leaf patch beside a one-megabyte unchanged value and all thirty useful string copies in the 1,521-byte reuse case. Their round trips remain about 14.8 and 4.1 ms. Complete repeated containers have already coalesced to one operation, so optional estimation is skipped; their roughly 1.58 ms round trip remains close to the default.

There are accepted costs when estimation finds no smaller encoding. Floating-point sizing keeps the same 24 operations and 1,133 bytes, but generation rises 0.1508 → 0.2107 ms (ratio 1.414), and round trip 0.2786 → 0.3544 ms (ratio 1.228, range 1.217–1.566). Formatting numeric literals costs work even when copies remain preferable. The full-generation unrelated-key object case retains its 78,781-byte patch, with generation 1.957 → 2.113 ms (ratio 1.085); the estimate reaches its byte cap. The repository fixture also retains its 2,097 operations/180,851 bytes because it exceeds both optional size/count limits. The option is not a general dense-subtree optimizer.

### Compression, memory, noise, and the release reference

**Raw-byte savings can increase compressed size.** At 50% density, the generation row's median gzip size rises from 2,668 to 4,857 bytes even though raw bytes fall from 24,001 to 13,538: the root replacement includes unchanged fields. The 1,000-property rename case shrinks from 31,651 to 28,225 raw bytes but grows from 4,249 to 8,892 gzip bytes. At 90%, gzip improves only modestly, from 4,861 to 4,673 bytes in the generation row. This is a reason to keep the policy explicit and measure the actual transport; it does not optimize gzip.

No median raw size increases in the retained default or option comparisons. Default quick gzip deltas range from −3,196 to +52 bytes and full-generation deltas from −29,201 to +189 bytes. The largest default increase is the 1,000-record prepend: raw bytes fall 97,080 → 97,030 while gzip medians rise 9,678 → 9,867. Independent object-operation/key order can also affect compression. Option full-generation gzip deltas range from −749 to +4,643 bytes.

Dedicated-worker peak-RSS differences for the default range from −0.59 to +0.45 MiB in quick measurements, −1.61 to +0.02 MiB in full generation, and −3.13 to +0.06 MiB in the selected large arrays. The largest default full-generation peak is 14.39 MiB. Option quick differences range from −0.11 to +0.16 MiB and full-generation differences from −0.05 to +0.20 MiB, with a largest option full-generation peak of 14.45 MiB. These include runtime, prepared inputs, and mode-specific prepared patches; they are not exact library allocations or worst-case memory guarantees.

Fresh stage-4 noise has median absolute paired deviation 1.46%, with maximum 48.02% in the object-copy-hit case. Current-default noise has median 1.90%, with maximum 47.16% in that case. Stage 3's [controlled equality-order investigation](stage3-macos-arm64-swift6.4.2.md#investigating-the-object-case-variance) explains the known copy-case sensitivity. Other outliers include the deep singleton chain (22.62% in the stage-4 noise capture) and sub-microsecond root changes (up to 19.60%). The maximum is not a universal acceptance threshold. Do not infer copy-lookup or tiny-case improvements from these noisy rows, or treat capped batch averages as request latencies.

Against v2.0.0 with this same harness, quick generation changes 3.387 → 1.575 ms for the 1,000-number prepend, 56.892 → 3.297 ms for 1,000-source copy misses, and 17.477 → 7.103 ms for the repository fixture. These cumulative improvements include stages 2–4; the stage-4 comparison above isolates stage 5.


## Alternatives and public-option decision

The cutoff experiment compares structural coalescing at 32 versus two direct replacements. It has 49 paired rows, including all seven measurements for seven cases. A ten-element reversal changes 401 → 58 bytes and round trip 0.1030 → 0.0662 ms; a ten-field complete object changes 461 → 158 bytes and 0.0771 → 0.0371 ms; a 31-field object changes 1,427 → 410 bytes and 0.2144 → 0.0956 ms. Generation remains close or modestly improves. Partial semantic/mutable cases retain their patches. A higher cutoff gives up useful small-container quality without a measured throughput benefit, so retain two. Single replacements still preserve their focused paths.

Two root-selection prototypes, each with 77 paired rows, compare the stage-4 patch with a whole-document replacement. Both cap operations at 2,048 and saturate byte estimates at 65,536. The first constructs JSON-compatible operation dictionaries and reuses generic literal sizing; the second accounts for operation metadata/paths directly. Neither is the final combined public policy.

| Prototype case | Generic estimator generation ms | Direct estimator generation ms | Generic round trip ms | Direct round trip ms |
| --- | ---: | ---: | ---: | ---: |
| 1,000-field object, 50% changed | 1.938 → 4.268 | 1.993 → 2.863 | 4.516 → 5.280 | 4.540 → 3.919 |
| 1,000-field object, 90% changed | 2.010 → 5.397 | 2.032 → 2.940 | 6.378 → 6.393 | 6.401 → 4.118 |

Generic dictionary construction/size traversal can cost more than the application work saved. With repeated target containers it raises generation 0.080 → 3.697 ms and round trip 1.610 → 5.187 ms. That approach is rejected. Operation-specific accounting makes partial dense changes worthwhile, while the structural proof handles complete changes without scanning repeated values at all. The shipped option combines those techniques and adds explicit value/pointer depth checks; its actual measurements are reported separately above.

The measurements establish a recurring tradeoff for partially changed objects: operation-specific estimation spends more generation time but produces substantially fewer bytes and less application work at 50%, 90%, and 99% change density. The structural default avoids that extra work. This justifies one opt-in public policy, `preferSmallerPatch`, rather than making estimation mandatory for every caller.

The public policy combines the retained structural default with the operation-specific estimator, adds explicit value/pointer depth limits, and preserves compact copies before comparing the root replacement. Complete changes usually coalesce before optional estimation and therefore avoid its cost. The scope is deliberately documented: it may replace the whole document, it is not a globally minimal subtree planner, and it targets default raw JSON bytes rather than gzip. No threshold, work-budget, positional-array, or move-generation controls are added. Broader subtree cost planning remains outside the retained implementation.

## Compatibility and release implications

Both existing generation initializers and their reading options retain their signatures. Additive overloads accept `generationOptions: [GenerationOption]`; passing an empty array uses the default. `GenerationOption` is `Equatable` and `Sendable`. Tests retain references to the original initializer function types. Swift/package deployment settings and dependencies are unchanged. Generation still produces an RFC 6902 patch that transforms source into target, preserves its prepared inputs, and can be serialized and reused. It does not promise a globally minimal patch or stable operation order/bytes.

Consumers that inspect paths or operation types must handle a container replacement covering multiple changed descendants. For example, two changed scalar fields can now produce a replacement of their containing object. This is an intentional output-quality change. The [usage guide](../../Docs/Usage.md#generate-a-json-patch-from-the-differences-between-two-json-documents) and initializer comments document it.

Target the proposed changes for **v2.1.0**, with release notes calling out copy-size selection, array edit sequences, and adaptive container replacements. The public option is an additive API suitable for a minor release. This is a release recommendation, not a version bump or tag: `master` remains the released v2.0.0 commit, `develop` remains unchanged, and the maintainer still selects the work for merging/release. Cross-platform acceptance and Apple distribution checks remain prerequisites to release.

## Validation and reproduction

- All 135 ordinary tests pass in Debug and Release with compiler warnings treated as errors, and all 135 pass in the macOS Xcode target.
- Both policies pass all 376 full-corpus case/mutability combinations: 752 checks with independent result comparison, serialization/application, input preservation, and reuse.
- The 128 seeded document pairs run under both policies across four mutability combinations, for 1,024 policy/mutability checks.
- Focused additions cover complete versus partial changes, unchanged external donors, escaped/Unicode keys, repeated target values, both initializer families, original initializer references, empty options, strict size ties, actual Foundation operation sizes, and byte/count/depth limits.
- All seven Swift benchmark-support tests and all 15 Python harness tests pass. Exported historical cutoff variants reproduce their recorded library-content hashes, and the optional adapter's policy source matches the retained implementation.
- All 1,059 paired rows pass, including separate memory workers; no timeout or memory-limit failure is omitted.
- Linux and supported Xcode 16.2/26.3 validation remain pending while work stays local. Apple distribution checks remain pending before release; this is local macOS acceptance, not cross-platform completion.

The corpus is version 4: 36 quick and 94 full cases. It adds complete object changes at small and large sizes, 10/50/90/99% change densities, large changed strings, repeated target containers, sparse changes beside a one-megabyte payload, and a nested reversal beside unchanged data. Earlier fixture bytes remain unchanged, but IDs and the harness hash change. Use the same harness for both sides of a comparison; do not compare historical corpus reports directly.

Run captures serially on the same idle machine. Standard captures use three alternating process pairs, five samples, a 10 ms sample target, one warmup, at most 1,000 iterations per sample, a 180-second worker timeout, and a 1,024 MiB RSS ceiling. Some tiny measurements cannot accumulate 10 ms before the iteration cap; flags and actual ranges remain in the report. The lower cap bounds repeated input restoration outside the in-place timer, particularly for the large sparse payload. Memory polling is enabled. Raw results remain ignored locally.

```sh
python3 Scripts/benchmark-patch-generation.py --profile full --validate-only \
  --output Benchmarks/Results/stage5-validation
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref d73c5f2 --library-ref d73c5f2 --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --max-iterations 1000 \
  --warmup 1 --timeout-seconds 180 --output Benchmarks/Results/stage5-noise-final
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref d73c5f2 --mode all \
  --processes 3 --samples 5 --sample-ms 10 --max-iterations 1000 \
  --warmup 1 --timeout-seconds 180 --output Benchmarks/Results/stage5-quick
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref d73c5f2 --profile full --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --max-iterations 1000 \
  --warmup 1 --timeout-seconds 180 --output Benchmarks/Results/stage5-full-generation
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref d73c5f2 --profile full --mode all \
  --case arrays/prepend-n10000 --case arrays/insert-n10000 \
  --case arrays/delete-n10000 --case arrays/reverse-n10000 \
  --processes 3 --samples 5 --sample-ms 10 --max-iterations 1000 \
  --warmup 1 --timeout-seconds 180 --output Benchmarks/Results/stage5-large-arrays
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref v2.0.0 --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --max-iterations 1000 \
  --warmup 1 --timeout-seconds 180 --output Benchmarks/Results/stage5-release-generation
```

Export both historical cutoff variants with `Scripts/evaluate-patch-generation-strategy.py --base-ref d73c5f2 --strategy complete-32 --output FIRST_DIRECTORY` and `--strategy complete-small --output SECOND_DIRECTORY`. Compare those paths with the full profile, all modes, and cases `complete-object-n10/`, `complete-object-n31/`, `complete-object-n32/`, `arrays/reverse-n10/`, `integer-boundaries`, `matching-semantic`, and `nested-source-mutable-target-mutable`. Use three pairs/five samples/10 ms/one warmup, with the historical 10,000-iteration cap and 180-second timeout. The exporter reconstructs these pre-API prototypes exactly from stage 4; both content hashes match the captured experiment.

For root estimators, export `--strategy root-size` or `--strategy root-size-direct` with `--base-ref d73c5f2`. Compare the result using `--baseline-library-path . --baseline-ref d73c5f2 --library-path NEW_DIRECTORY --profile full --mode all`. Select cases with repeated `--case` values: `complete-object-n1000/`, `density`, `complete-large-strings`, `complete-repeated-containers`, `two-leaves-beside`, `nested-reversal-beside`, `hit-string-bytes`, and `arrays/reverse-n1000/`. Use the standard settings above. These variants are based on stage 4 to isolate estimator costs; their complete-change cases do not represent a combined stage 5 policy.

The public-option capture uses a temporary adapter exported by `--strategy prefer-smaller`. It redirects the harness's existing Element initializer to the public `generationOptions: [.preferSmallerPatch]` overload; the Data initializer delegates through that call too. Policy code is unchanged and the actual public initializer runs under normal Release optimization. Both the adapter manifest and its distinct source hash are retained. Export and measure it with:

```sh
python3 Scripts/evaluate-patch-generation-strategy.py --strategy prefer-smaller \
  --output /tmp/jsonpatch-stage5-prefer-smaller
python3 Scripts/benchmark-patch-generation.py \
  --baseline-library-path . --library-path /tmp/jsonpatch-stage5-prefer-smaller --mode all \
  --processes 3 --samples 5 --sample-ms 10 --max-iterations 1000 \
  --warmup 1 --timeout-seconds 180 --output Benchmarks/Results/stage5-option-quick
python3 Scripts/benchmark-patch-generation.py \
  --baseline-library-path . --library-path /tmp/jsonpatch-stage5-prefer-smaller \
  --profile full --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --max-iterations 1000 \
  --warmup 1 --timeout-seconds 180 --output Benchmarks/Results/stage5-option-full-generation
python3 Scripts/benchmark-patch-generation.py \
  --library-path /tmp/jsonpatch-stage5-prefer-smaller --profile full --validate-only \
  --output Benchmarks/Results/stage5-option-validation
```

Also capture current-default versus itself before judging option costs: use the noise command with `--baseline-library-path . --library-path .` in place of both revision arguments, and output `stage5-noise-default`.

The additional public-option capture uses `--profile full --mode all` with cases `object-n1000-density10`, `object-n1000-density50`, `object-n1000-density99`, and `floating-literal-cost`, the same adapter/baseline paths and standard settings, and output `stage5-option-targeted`.
