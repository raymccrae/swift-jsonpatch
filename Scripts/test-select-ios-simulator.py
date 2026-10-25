"""Regression tests for selecting simulators with multiple installed Xcodes."""
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "selector", pathlib.Path(__file__).with_name("select-ios-simulator.py")
)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


class SimulatorSelectionTests(unittest.TestCase):
    def setUp(self):
        self.data = {
            "runtimes": [
                {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
                 "version": "26.2", "isAvailable": True},
                {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
                 "version": "18.2", "isAvailable": True,
                 "supportedDeviceTypes": [
                     {"name": "iPad Pro", "identifier": "ipad"},
                     {"name": "iPhone 16", "identifier": "iphone16"}]},
            ],
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                    {"name": "iPhone 17", "udid": "wrong-xcode", "isAvailable": True}],
                "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
                    {"name": "iPhone 16", "udid": "compatible", "isAvailable": True}],
            },
        }

    def test_ignores_wrong_runtime_even_when_it_appears_first(self):
        self.assertEqual(selector.select_device(self.data, "18.2"), "compatible")

    def test_skips_unavailable_device(self):
        devices = self.data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-18-2"]
        devices.insert(0, {"name": "iPhone 16", "udid": "unavailable", "isAvailable": False})
        self.assertEqual(selector.select_device(self.data, "18.2"), "compatible")

    def test_rejects_unavailable_runtime(self):
        self.data["runtimes"][1]["isAvailable"] = False
        with self.assertRaisesRegex(ValueError, "18.2"):
            selector.select_device(self.data, "18.2")

    def test_reports_no_compatible_runtime(self):
        with self.assertRaisesRegex(ValueError, "18.1"):
            selector.select_device(self.data, "18.1")

    def test_reports_no_available_iphone(self):
        self.data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-18-2"] = []
        with self.assertRaisesRegex(ValueError, "iPhone"):
            selector.select_device(self.data, "18.2")

    def test_accepts_equivalent_sdk_patch_version(self):
        self.assertEqual(selector.select_device(self.data, "18.2.0"), "compatible")

    def test_accepts_older_runtime_in_same_sdk_major(self):
        self.assertEqual(selector.select_device(self.data, "18.3"), "compatible")

    def test_accepts_27_0_runtime_with_27_1_sdk(self):
        self.data["runtimes"][0]["version"] = "27.0"
        self.data["runtimes"][0]["identifier"] = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
        self.data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-27-0"] = [
            {"name": "iPhone 17", "udid": "local-27", "isAvailable": True}]
        self.assertEqual(selector.select_device(self.data, "27.1"), "local-27")

    def test_excludes_future_runtime_in_same_sdk_major(self):
        self.data["runtimes"].insert(0, {
            "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-3",
            "version": "18.3", "isAvailable": True})
        self.data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-18-3"] = [
            {"name": "iPhone 16", "udid": "future", "isAvailable": True}]
        self.assertEqual(selector.select_device(self.data, "18.2"), "compatible")

    def test_prefers_newest_compatible_runtime(self):
        self.data["runtimes"].append({
            "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-1",
            "version": "18.1", "isAvailable": True})
        self.data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-18-1"] = [
            {"name": "iPhone 16", "udid": "older", "isAvailable": True}]
        self.assertEqual(selector.select_device(self.data, "18.3"), "compatible")

    def test_creation_uses_device_type_supported_by_matching_runtime(self):
        self.assertEqual(selector.creation_arguments(self.data, "18.2"),
                         ["iPhone JSONPatch CI", "iphone16", "com.apple.CoreSimulator.SimRuntime.iOS-18-2"])

    def test_created_simulator_can_be_selected_on_next_invocation(self):
        name, _, runtime = selector.creation_arguments(self.data, "18.2")
        self.data["devices"][runtime] = [
            {"name": name, "udid": "created-device", "isAvailable": True}]
        self.assertEqual(selector.select_device(self.data, "18.2"), "created-device")


if __name__ == "__main__":
    unittest.main()
