"""Exercise provisioning with fake Xcode tools and the real simulator selector."""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("prepare-ios-simulator.sh")
AVAILABLE = {"runtimes": [{
    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
    "version": "18.2", "isAvailable": True}], "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
            {"name": "iPhone 16", "udid": "ready-device", "isAvailable": True}]}}


class ProvisioningTests(unittest.TestCase):
    def run_provisioning(self, *, installed=False, modern=False, installs=True, status=0):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "available.json").write_text(json.dumps(AVAILABLE))
            (root / "empty.json").write_text('{"runtimes": [], "devices": {}}')
            if installed:
                (root / "installed").touch()
            (root / "xcrun").write_text("""#!/bin/bash
set -eu
if [[ "$*" == '--sdk iphonesimulator --show-sdk-version' ]]; then
    echo 18.2
elif [[ "$*" == 'simctl list --json' ]]; then
    if [[ -f "$FIXTURE_ROOT/installed" ]]; then
        cat "$FIXTURE_ROOT/available.json"
    else
        cat "$FIXTURE_ROOT/empty.json"
    fi
else
    exit 99
fi
""")
            (root / "xcodebuild").write_text("""#!/bin/bash
set -eu
if [[ "$*" == '-help' ]]; then
    echo '-downloadPlatform -buildVersion'
    if [[ "$MODERN_XCODE" == 1 ]]; then echo '-architectureVariant'; fi
    exit 0
fi
printf '%s\\n' "$*" >> "$FIXTURE_ROOT/downloads"
if [[ "$INSTALLS_RUNTIME" == 1 ]]; then touch "$FIXTURE_ROOT/installed"; fi
exit "$DOWNLOAD_STATUS"
""")
            for name in ("xcrun", "xcodebuild"):
                (root / name).chmod(0o755)
            result = subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True,
                                    env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                                         "FIXTURE_ROOT": str(root), "MODERN_XCODE": str(int(modern)),
                                         "INSTALLS_RUNTIME": str(int(installs)),
                                         "DOWNLOAD_STATUS": str(status)})
            log = root / "downloads"
            return result, log.read_text().splitlines() if log.exists() else []

    def test_existing_simulator_skips_download(self):
        result, downloads = self.run_provisioning(installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ready-device", result.stdout)
        self.assertEqual(downloads, [])

    def test_legacy_xcode_download_omits_unsupported_architecture_option(self):
        result, downloads = self.run_provisioning()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(downloads, ["-downloadPlatform iOS -buildVersion 18.2"])
        self.assertIn("ready-device", result.stdout)

    def test_modern_xcode_uses_supported_architecture_option(self):
        result, downloads = self.run_provisioning(modern=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(downloads, ["-downloadPlatform iOS -buildVersion 18.2 -architectureVariant universal"])

    def test_nonzero_download_succeeds_only_when_simulator_becomes_available(self):
        result, _ = self.run_provisioning(status=70)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ready-device", result.stdout)

    def test_failed_download_without_runtime_fails(self):
        result, _ = self.run_provisioning(status=70, installs=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("70", result.stderr)

    def test_successful_download_without_runtime_still_fails(self):
        result, _ = self.run_provisioning(installs=False)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
