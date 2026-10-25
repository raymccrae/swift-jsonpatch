"""Select an iPhone from an available runtime compatible with Xcode's SDK."""
import argparse
import json
import subprocess
import sys


def version(value):
    parts = [int(part) for part in value.split(".")]
    while parts and parts[-1] == 0:
        parts.pop()
    return parts


def matching_runtime(data, sdk_version):
    sdk = version(sdk_version)
    # Runners may retain runtimes from newer Xcodes. Stay within this SDK's
    # major release and prefer its newest installed runtime, never a newer OS.
    for runtime in sorted(data["runtimes"], key=lambda item: version(item["version"]), reverse=True):
        runtime_version = version(runtime["version"])
        if (runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                and runtime.get("isAvailable", False)
                and runtime_version[0] == sdk[0] and runtime_version <= sdk):
            return runtime
    raise ValueError(
        f"No available iOS runtime compatible with SDK {sdk_version}. "
        f"Install it with: xcodebuild -downloadPlatform iOS -buildVersion {sdk_version}"
    )


def select_device(data, sdk_version):
    runtime = matching_runtime(data, sdk_version)
    for device in data["devices"].get(runtime["identifier"], []):
        if device.get("isAvailable", False) and device["name"].startswith("iPhone"):
            return device["udid"]
    raise ValueError(f"No available iPhone simulator for iOS {sdk_version}. "
                     "Run this script with --create-if-needed to create one.")


def creation_arguments(data, sdk_version):
    runtime = matching_runtime(data, sdk_version)
    for device_type in runtime.get("supportedDeviceTypes", []):
        if device_type["name"].startswith("iPhone"):
            return ["iPhone JSONPatch CI", device_type["identifier"], runtime["identifier"]]
    raise ValueError(f"No supported iPhone device type for iOS {sdk_version}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sdk_version", help="xcrun --sdk iphonesimulator --show-sdk-version")
    parser.add_argument("--create-if-needed", action="store_true")
    args = parser.parse_args()
    data = json.load(sys.stdin)
    try:
        try:
            device = select_device(data, args.sdk_version)
        except ValueError:
            if not args.create_if_needed:
                raise
            device = subprocess.check_output(
                ["xcrun", "simctl", "create", *creation_arguments(data, args.sdk_version)],
                text=True,
            ).strip()
        print(device)
    except ValueError as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
