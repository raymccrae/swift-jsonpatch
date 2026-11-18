# Stage 3: copy lookup and encoding choices

Retain the local stage 3 implementation. Large unsuccessful copy searches improve substantially, useful large-value copies remain compact, and tiny literals avoid oversized copies. Some small searches and collision-heavy containers pay extra generation cost; those tradeoffs are recorded below. The public API and positional array-edit strategy are unchanged.

The primary comparison is stage 2, commit `812eb7e25e11bbc2572674a91ce848fdbd1b38aa`. A supplementary generation comparison uses v2.0.0. The [machine-readable report](stage3-macos-arm64-swift6.4.2.json) retains every standard comparison row, process medians and sample ranges, operation counts, raw/gzip sizes, dedicated memory measurements, diagnostics, and the controlled equality-order experiment.

## Implementation

The [generator](../../Sources/JSONPatch/JSONPatchGenerator.swift) retains stage 2's comparison plan and maximal unchanged sources. Copy resolution still replaces additions in place. It never indexes newly added values, and it preserves the existing sequential-path invariant: object edits do not rename stable keys, and positional arrays remove only their tails and append at the end. Future array matching must revisit source validity.

Sources carry their escaped pointer spelling and its default JSON-encoded byte count. Actual searches order sources by that cost, then by Unicode scalar spelling to break ties. The first exactly equal source is therefore a stable, shortest encoded choice among the safe candidates. Queries that cannot beat the shortest available path are rejected before sorting or indexing. Literals of at most four encoded bytes cannot benefit from any non-root copy source, so those additions also skip source collection and unchanged-path construction.

Lookup starts linearly. An index is built only after at least 64 source comparisons have occurred, with at least 16 sources and two queries still to serve. Cheap hits and single-query searches avoid index construction. Index setup is part of measured generation, not a preparation step.

Fingerprints are filters, not equality or persistent identifiers:

- Strings include UTF-16 length and the first 32 Unicode scalars.
- Arrays include count and at most eight children, with a two-level structural depth budget.
- Objects with at most eight fields combine key/value fingerprints independently of field order. Larger objects contribute type and count. Key spellings are hashed by Unicode scalar sequence; work on a key remains proportional to its length.
- Numeric values share a tag so integer, floating-point, and decimal representations cannot exclude an equal number. Booleans have a separate tag. This deliberately makes numeric containers prone to collisions.
- Every bucket match receives the existing exact JSON equality check, including single-entry buckets. A bucket containing at least half the sources disables the index for the rest of that call, avoiding repeated unselective hashing.

The cost policy is **strictly fewer bytes under default compact `JSONPatch.data()` serialization**. The add/copy operation metadata has equal size: the extra byte in `copy` cancels the shorter `from` field name. Destination cost is shared. Therefore a copy wins exactly when the quoted, escaped source pointer is smaller than the literal value. Ties retain the literal. Tests compare this algebra with actual serialized operations, including escaped paths and numeric formatting.

Literal estimates saturate as soon as they exceed the source-path budget; large arrays/objects can often be rejected by minimum-size bounds. Integer digit counts use signed/unsigned magnitude without conversion through `Double`. Floating-point and decimal formatting is delegated to Foundation and cached per immutable NSNumber identity during the call. Early prototypes repeatedly formatted numbers; that overhead was rejected before the final capture. Alternate serializer options and gzip size are not the selection policy.

## Measurements

Measurements use an Apple M5 Pro, macOS 27.0.1, Xcode 27.2, and Apple Swift 6.4.2. Both libraries use the same Release harness, corpus, compiler flags, and settings. The measured candidate is a dirty working tree based on stage 2; its library content SHA-256 is `300aa0aba4d00b7d12a1c7d3567792036dd80a48f36f627d6700145d92c91e24`. That content matches the source accompanying this report.

Corpus version 2 adds twelve cases for indexed hits/misses, one-query searches, prefix collisions, numeric containers, floating-point sizing, shortest escaped donors, and byte-size boundaries. It has 21 quick cases and 71 full cases. Existing case bytes are unchanged; their versioned IDs and the harness hash change. Old v1 reports must not be directly compared with v2 reports. All library revisions in these captures use the same v2 harness.

There are 260 standard paired rows: 21 stage-2-versus-stage-2 generation noise cases, 147 quick case/measurement combinations against stage 2, 71 full generation cases against stage 2, and 21 quick generation cases against v2.0.0. Each has three alternating process pairs, five samples per process, a 10 ms calibration target, one warmup, and a separate memory worker. All passed, with no timeouts or memory-limit breaches. Full-corpus serialization/application/round-trip timings were not captured; all full cases receive correctness round trips and generation size/memory measurements.

Times are milliseconds, summarized as the median of process medians. Ratios are medians of paired candidate/baseline ratios, so they need not equal the quotient of the displayed times. Ranges are observed process-pair variation, not confidence intervals or request-latency percentiles.

| Generation case | Stage 2 ms | Stage 3 ms | Paired ratio | Pair range |
| --- | ---: | ---: | ---: | ---: |
| 300 misses among 1,000 sources | 53.318 | 3.199 | 0.060 | 0.059–0.061 |
| 3,000 misses among 10,000 sources | 5,174.150 | 34.376 | 0.007 | 0.007–0.007 |
| 24 string hits among 64 sources | 0.564 | 0.472 | 0.836 | 0.818–0.856 |
| Thirty copies of a 10 KB string | 3.244 | 3.266 | 1.006 | 1.000–1.031 |
| Tiny number with a long escaped donor path | 0.0145 | 0.0114 | 0.779 | 0.772–0.803 |

The 1,000-source miss case's complete round trip drops from 56.045 ms to 5.172 ms, with paired ratios 0.089–0.106. Its raw patch remains 16,991 bytes with 300 additions; this is a lookup gain rather than a patch-shape change. The 10,000-source miss case retains its 172,891-byte patch with 3,000 additions. Large-string reuse retains all 30 copies and the same 1,521-byte patch without building an index.

Against v2.0.0 with this same v2 harness, quick generation takes 57.213 → 3.387 ms for the 1,000-source miss case, 5.323 → 1.969 ms for the sparse 1,000-property edit, and 18.879 → 6.893 ms for the repository fixture. The latter two benefits largely come from stage 2; the primary incremental comparisons isolate stage 3.

### Encoding, application, and accepted costs

The long escaped-source case drops from a 204-byte copy patch to a 41-byte literal patch. In-place application drops from 0.00204 to 0.00125 ms, application on a copy from 0.00304 to 0.00227 ms, and the complete round trip from 0.0294 to 0.0199 ms. The byte-boundary fixture drops from 415 to 409 bytes; ties now use literals. Its in-place application improves from 0.0133 to 0.0108 ms, while its round-trip time stays close to stage 2.

No median raw patch size increases in the captured comparisons. Some operation types intentionally change from copy to add. Gzip median differences range from −168 to +99 bytes across quick rows and −13 to +19 bytes across full-generation rows. Operation order, equivalent donor choice, and compression can vary; raw-byte savings do not guarantee compressed savings.

The retained implementation has observed generation overhead in several cases:

| Generation case | Stage 2 ms | Stage 3 ms | Paired ratio | Pair range |
| --- | ---: | ---: | ---: | ---: |
| One string miss among 1,000 sources | 2.917 | 3.109 | 1.062 | 1.056–1.078 |
| Numeric arrays with deliberately coarse fingerprints | 6.439 | 6.875 | 1.068 | 1.060–1.068 |
| Indexed array hits | 3.827 | 4.007 | 1.047 | 0.978–1.083 |
| Thirty large-integer copies | 0.0368 | 0.0388 | 1.053 | 1.040–1.088 |
| Floating-point literal sizing | 0.1532 | 0.1544 | 1.032 | 1.007–1.089 |

The single-miss case avoids an index but still pays for source spelling, ordering, and size checks. Numeric-array fingerprints intentionally collide; the attempted index falls back to exact linear search. Integer-copy overhead is about two microseconds per generation here. These costs are accepted for the large miss improvements, stable source selection, and smaller literal encodings. They remain reasons to keep the small-search path and bounded filters; no universal speedup is claimed.

Quick peak-RSS differences range from about −0.09 to +0.19 MiB. Full-generation differences range from −1.88 to +0.94 MiB. The largest increase is the 10,000-source miss case; the largest candidate full-generation peak is 14.52 MiB. These are maximum dedicated-worker process peaks, including runtime and prepared inputs, not allocation attribution or library-only bounds. Source arrays, buckets, and numeric costs are released with the generation call.

### Investigating the object-case variance

The fresh identical-library run has median absolute paired deviation 1.5%, but maximum deviation 572.4%. That maximum is confined to the new object-hit fixture: its ratios span 0.157–6.724. Other noise cases have a maximum deviation of about 8.2%. The differing ID shares an object with an equal 32-element array and an equal string. Stage 2's exact equality iterates a key set and stops at the first difference, so process-specific visitation order can substantially change the work before an unsuccessful match. The default object-hit comparison has a median ratio of 0.345 but a range of 0.309–1.944; it does not justify an unconditional container-speedup claim. The numeric-object fixture also has broad variation.

To investigate, temporary copies of both libraries ordered exact-equality keys with the ID first or last. These diagnostic runs used `SWIFT_DETERMINISTIC_HASHING=1`, five process pairs, nine samples, a 20 ms target, and two warmups. Both variants paid the ordering cost. They are not default production timings:

| Controlled mismatch order | Stage 2 ms | Stage 3 ms | Paired ratio | Pair range |
| --- | ---: | ---: | ---: | ---: |
| ID first | 4.006 | 3.725 | 0.930 | 0.909–0.933 |
| ID after the equal array/string | 25.059 | 7.005 | 0.280 | 0.274–0.282 |

This supports equality visitation order as the explanation for the broad default-case spread, and shows why filtering helps more when failed structural comparisons are expensive. The controlled sources and environment differ from the production capture; use them to explain sensitivity rather than combine them into a performance score. Raw controlled reports are retained under `Benchmarks/Results/stage3-order-id-first/` and `stage3-order-id-last/`. Reproduce by exporting both revisions, replacing the single `for key in keysA` loop in `valuesEqual` with the same ID-first/ID-last ordering in both temporary libraries (the fixture's keys are ASCII), then running the paired runner on `indexed-hit-object-n32-add24` with those paths and the recorded settings.

## Untimed work diagnostics

[diagnose-patch-generation.py](../../Scripts/diagnose-patch-generation.py) builds an instrumented temporary source copy, leaving the checkout unchanged. Diagnostic logging and global counters are absent from the timed library. The companion JSON includes the generator/instrumentation hashes, source/addition counts and types, encoded value-size ranges, search hit rates, and equality counts.

| Case | Collected sources | Additions | Searches / hits | Index built | Work observed |
| --- | ---: | ---: | ---: | --- | --- |
| 10,000-source misses | 10,000 strings | 3,000 strings | 3,000 / 0 | Yes | 10,000 exact comparisons; stage 2's full misses require 10,000 × 3,000 = 30 million. Added values encode to 13–16 bytes. |
| Large-string copies | One 10,002-byte value | 30 strings | 30 / 30 | No | Thirty exact comparisons; cheap hits stay linear. |
| Tiny number / long path | Zero after cheap-literal filtering | One number | No search | No | No equality work or source collection; one literal add. |

Counts are observations from the instrumented run, not worst-case complexity guarantees. Fingerprint collisions can still require linear search. Recursive equality counts include child checks for containers. The numeric cache is local to one call; floating-point diagnostics record 24 cached costs for 24 additions.

## Validation and reproduction

- All 113 ordinary tests pass in Debug and Release with compiler warnings treated as errors. Coverage includes forced collisions, compatible numeric fingerprints, Unicode scalar identity, serialized size boundaries, deterministic source choice, sequential array-source validity, patch reuse, and the existing seeded documents.
- All 113 tests pass in the macOS Xcode target with the same command-line deployment override used for stage 2. Library deployment settings are unchanged.
- All 284 full-corpus mutability combinations pass independent result checks, serialization, reuse, and input-preservation checks.
- All seven Swift benchmark-support tests and all 13 Python harness tests pass.
- Linux and the supported Xcode 16.2/26.3 matrix remain pending because the branch is local. Do not assume macOS timings transfer to corelibs Foundation.

Run these serially on the same idle machine. Each timed worker has a 180-second timeout and a 1,024 MiB RSS ceiling; resident-memory polling is enabled in the captures. Use the stage 3 commit introducing this report, or matching library/harness content hashes.

```sh
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref 812eb7e --library-ref 812eb7e --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage3-noise-final
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref 812eb7e --mode all \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage3-quick
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref 812eb7e --profile full --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage3-full-generation
python3 Scripts/benchmark-patch-generation.py \
  --baseline-ref v2.0.0 --mode generate \
  --processes 3 --samples 5 --sample-ms 10 --warmup 1 --timeout-seconds 180 \
  --output Benchmarks/Results/stage3-release-generation
python3 Scripts/diagnose-patch-generation.py
```

Full samples remain ignored under `Benchmarks/Results/`. Compact per-process arrays follow each row's `process_pair_ids`. There is no combined performance score or automatic timing gate. Stages 4–5 remain proposed; this change does not implement array matching or adaptive subtree replacement.
