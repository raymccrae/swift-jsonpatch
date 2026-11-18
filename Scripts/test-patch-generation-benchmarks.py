"""Harness regression tests. Run with Python 3.9 or newer."""
import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock

import patch_generation_benchmark as support

spec = importlib.util.spec_from_file_location("comparison", pathlib.Path(__file__).with_name("compare-patch-generation.py"))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)
summary_spec = importlib.util.spec_from_file_location("baseline_summary", pathlib.Path(__file__).with_name("summarize-patch-generation-baseline.py"))
baseline_summary = importlib.util.module_from_spec(summary_spec)
summary_spec.loader.exec_module(baseline_summary)


class CorpusTests(unittest.TestCase):
    def test_quick_covers_every_family_and_has_unique_ids(self):
        cases = support.corpus()
        self.assertEqual(len(cases), len({case["id"] for case in cases}))
        self.assertEqual({case["family"] for case in cases},
                         {"unchanged", "sparse", "objects", "copies", "encoding", "arrays", "dense", "mutable", "semantics", "fixtures"})
        for case in cases:
            json.loads(case["source"])
            json.loads(case["target"])

    def test_raw_semantics_preserve_unicode_keys_and_adjacent_integers(self):
        cases = {case["name"]: case for case in support.corpus()}
        self.assertEqual(json.loads(cases["unicode-keys"]["source"]), {"\u00e9": 1, "e\u0301": 2})
        self.assertIn(b"18446744073709551615", cases["integer-boundaries"]["source"])
        self.assertIn(b"18446744073709551614", cases["integer-boundaries"]["target"])

    def test_full_contains_quick_and_corpus_is_repeatable(self):
        first = support.corpus("full")
        self.assertEqual(first, support.corpus("full"))
        self.assertLess({c["id"] for c in support.corpus()}, {c["id"] for c in first})
        self.assertTrue(any("n10000" in case["id"] for case in first))

    def test_copy_lookup_corpus_has_hits_misses_and_prefix_collisions(self):
        cases = {case["name"]: case for case in support.corpus("full")}
        for name in ("indexed-hit-string-n64-add24", "single-hit-string-n1000-add1"):
            source, target = [json.loads(cases[name][key]) for key in ("source", "target")]
            additions = [value for key, value in target.items() if key not in source]
            self.assertTrue(additions)
            self.assertTrue(all(value in source.values() for value in additions))
        for name in ("indexed-miss-string-n64-add24", "single-miss-string-n1000-add1"):
            source, target = [json.loads(cases[name][key]) for key in ("source", "target")]
            self.assertTrue(all(value not in source.values() for key, value in target.items() if key not in source))
        source = json.loads(cases["indexed-hit-prefix-collision-n64-add24"]["source"])
        self.assertEqual(len(set(source.values())), 64)
        self.assertEqual(len({(len(v), v[:32]) for v in source.values()}), 1)


class ProcessTests(unittest.TestCase):
    def test_interrupt_reaps_the_worker(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            binary = directory / "worker"
            binary.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
            binary.chmod(0o755)
            settings = dict(samples=1, sample_ms=1, warmup=0, max_iterations=1,
                            timeout_seconds=10, memory_limit_mb=1024)
            processes = []
            popen = support.subprocess.Popen
            def capture(*args, **kwargs):
                process = popen(*args, **kwargs)
                processes.append(process)
                return process
            with mock.patch.object(support.subprocess, "Popen", side_effect=capture), \
                 mock.patch.object(support, "resident_bytes", return_value=0), \
                 mock.patch.object(support.time, "sleep", side_effect=KeyboardInterrupt):
                with self.assertRaises(KeyboardInterrupt):
                    support.run_worker(binary, dict(source=b"{}", target=b"{}", flags=[]), "generate", settings, directory)
            self.assertIsNotNone(processes[0].poll())

    def test_worker_timeout_is_reported(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            binary = directory / "worker"
            binary.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
            binary.chmod(0o755)
            settings = dict(samples=1, sample_ms=1, warmup=0, max_iterations=1,
                            timeout_seconds=0.1, memory_limit_mb=1024)
            case = dict(source=b"{}", target=b"{}", flags=[])
            result = support.run_worker(binary, case, "generate", settings, directory)
            self.assertEqual(result["status"], "timeout")

    def test_invalid_worker_output_is_not_a_fast_result(self):
        with self.assertRaises(ValueError):
            support.validate_worker(dict(worker_schema_version=1, mode="generate", validation="passed",
                                         memory_only=False, samples_ns=[]), "generate")


def report():
    case = support.case_metadata(support.corpus()[0])
    process = dict(status="passed", pair=0, samples_ns=[100, 110], patch_bytes=2,
                   patch_gzip_bytes=22, measurement_peak_rss_bytes=1000)
    row = dict(case=case, mode="generate", processes=[process], summary=support.summarize([process]))
    env = {key: "same" for key in ("system", "os", "architecture", "cpu", "swift", "xcode", "build_flags", "python", "zlib", "compression", "rss_polling_available")}
    return dict(schema_version=1, environment=env, harness=dict(sha256="harness"), settings={},
                library=dict(content_sha256="library", commit="commit"), results=[row])


class ComparisonTests(unittest.TestCase):
    def test_identical_library_is_noise_and_small_process_count_is_labeled(self):
        text = comparison.compare(report(), report())
        self.assertIn("baseline noise", text)
        self.assertIn("fewer than 3 pairs", text)

    def test_rejects_incompatible_environment_harness_or_fixture(self):
        for field in ("environment", "harness", "fixture"):
            first, second = report(), report()
            if field == "environment":
                second["environment"]["swift"] = "other"
            elif field == "harness":
                second["harness"]["sha256"] = "other"
            else:
                second["results"][0]["case"]["target_sha256"] = "other"
            with self.assertRaises(ValueError):
                comparison.compare(first, second)

    def test_missing_and_failed_cases_remain_visible(self):
        first, second = report(), report()
        second["results"] = []
        self.assertIn("MISSING", comparison.compare(first, second))
        second = report()
        second["results"][0]["summary"]["failed_processes"] = 1
        self.assertIn("FAILED", comparison.compare(first, second))

    def test_process_pair_mismatch_is_rejected(self):
        first, second = report(), report()
        second["results"][0]["processes"][0]["pair"] = 1
        with self.assertRaises(ValueError):
            comparison.compare(first, second)


class BaselineSummaryTests(unittest.TestCase):
    def reference(self):
        value = report()
        value["captured_at"] = "2026-11-18T00:00:00Z"
        value["library"].update(commit=support.REFERENCE, dirty=False)
        value["settings"].update(processes=3, validate_only=False)
        row = value["results"][0]
        for key in ("source_bytes", "target_bytes", "source_nodes", "target_nodes", "source_depth", "target_depth"):
            row["processes"][0][key] = 1
        row["processes"][0].update(operation_counts={}, iteration_limit_reached=False)
        row["processes"] = [dict(row["processes"][0], pair=pair) for pair in range(3)]
        row["summary"] = support.summarize(row["processes"])
        return value

    def test_exports_summary_and_observed_noise(self):
        result = baseline_summary.summarize(self.reference(), self.reference())
        self.assertEqual(result["validation"], "passed")
        self.assertEqual(result["observed_noise"]["maximum_absolute_pair_deviation"], 0)
        self.assertEqual(result["rows"][0]["noise_pair_ratios"], [1, 1, 1])

    def test_rejects_nonrelease_or_insufficient_pairs(self):
        for field in ("commit", "processes", "missing"):
            first, second = self.reference(), self.reference()
            if field == "commit":
                first["library"]["commit"] = "other"
            elif field == "processes":
                first["settings"]["processes"] = second["settings"]["processes"] = 1
            else:
                first["results"][0]["processes"].pop()
                second["results"][0]["processes"].pop()
            with self.assertRaises(ValueError):
                baseline_summary.summarize(first, second)


if __name__ == "__main__":
    unittest.main()
