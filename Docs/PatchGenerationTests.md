# Patch generation tests

Run the generation checks with the ordinary package tests. They also belong to the standalone Xcode test target; the benchmark package is not required.

```sh
swift test -Xswiftc -warnings-as-errors
swift test --configuration release -Xswiftc -warnings-as-errors
```

To run only the generation suites and their independent comparator tests, use:

```sh
swift test --filter 'JSONPatchGenerator|GenerationJSON' -Xswiftc -warnings-as-errors
```

## Correctness and quality expectations

The [focused quality tests](../Tests/JSONPatchTests/JSONPatchGeneratorQualityTests.swift), established before stage 2, protect useful output from the v2.0.0 generator as traversal changes are evaluated.

| Cases | Expectations |
| --- | --- |
| Single object and array edits | One appropriate operation, with the intended path and value. Include nested leaves, escaped and empty property names, missing versus null, Boolean versus number, large integers, and distinct Unicode spellings. |
| Root changes and unchanged documents | Root replacements address the whole document. Separately parsed equal documents produce no operations across all container-mutability combinations. |
| Disjoint object edits | The patch contains the expected edits without redundant operations. Independent operations may appear in any order. |
| Small edits beside large unchanged subtrees | One leaf replacement preserves the surrounding structure and stays below a generous 128-byte envelope. |
| Large duplicate strings, arrays, and objects | One compact `copy`, below 256 bytes, works with a stable donor before or after the addition in array traversal order. Equivalent donors may be chosen in any order. |
| Removals, replacements, and nested array transfers | Copy sources and array indices remain valid when the patch executes sequentially. |
| Mutable inputs across generation calls | Later generation sees changed input values rather than stale cached state, including shared mutable arrays and objects beneath different source/target roots. |
| Data initializer | Generation through the data API retains the focused operations and survives serialization and application. |

Exact operation expectations apply to deliberately simple cases. These are regression expectations, not a public promise of a globally minimal patch. Byte envelopes protect small patches and useful copies without fixing serialized field order. They are not timing thresholds.

The tests do not require the generator's inefficient positional output for prepends, middle insertions, or reordering. Those cases receive correctness coverage here and measurements in the [benchmark suite](../Benchmarks/README.md). Add improved-quality expectations alongside the later array algorithm. Likewise, choosing between tiny literals and long `copy` paths belongs to the later encoding policy.

Stage 2 adds regressions for an unchanged copy source beneath a changing ancestor, encountered before or after the addition, and for the identity shortcut on shared mutable subtrees. These tests pass against both the original release and the stage 2 implementation; they protect existing behavior rather than introduce a different copy policy.

## Seeded generated documents

The [generated-document suite](../Tests/JSONPatchTests/JSONPatchGeneratorGeneratedTests.swift) defines corpus version 1: four fixed seeds (`0`, `1`, `1729`, and `0xDEADBEEFCAFEBABE`) and 32 case indices per seed. Its 128 document pairs exercise 512 source/target mutability combinations. SplitMix64 with wrapping integer arithmetic and sorted Unicode scalar keys makes the document trees reproducible without Swift's randomized hashing.

Each case index modulo eight selects a family:

| Remainder | Family |
| --- | --- |
| 0 | Equal documents. |
| 1 | Unrelated documents, including root type changes. |
| 2 | Three edits to a generated document. |
| 3 | One nested leaf change beside unchanged generated subtrees; require one small replacement. |
| 4 | Reused values alongside another changing property. |
| 5 | Three array edits with duplicate values. |
| 6 | Transfers between nested arrays. |
| 7 | Nested replacements under escaped and empty property names. |

Base trees have at most three container levels and four children per container. Wrappers and edits add bounded structure. Values include empty containers, null, Boolean values, decimal and integer boundaries, escaped strings, and composed/decomposed Unicode keys and strings. Failure messages include the seed, case index, mutability combination, and source/target JSON. Rerun the corpus with:

```sh
swift test --filter JSONPatchGeneratorGeneratedTests/seededDocuments -Xswiftc -warnings-as-errors
```

## Independent result checks

[GenerationTestSupport.swift](../Tests/JSONPatchTests/GenerationTestSupport.swift) compares trees without the library's equality or pointer helpers. It compares keys and strings by Unicode scalar sequence, separates Boolean values from numbers, and compares numbers with `Decimal` rather than converting through `Double`. Its own boundary tests check those distinctions. The generated fixtures are also checked against their original value trees after encoding and parsing.

The shared check verifies generation preserves its inputs, applies both the original and serialized patch to fresh mutable and immutable documents, exercises `.applyOnCopy`, and checks that reuse preserves the patch and prepared inputs. The existing Unicode round-trip tests use this check as well.

Application still uses this library's patch interpreter. The independent comparator prevents shared equality mistakes from hiding an incorrect final document, but this is not an independent implementation of patch application or exhaustive testing. Numeric coverage is bounded to values supported by Foundation and `Decimal`; the corpus does not test arbitrary-precision JSON numbers.
