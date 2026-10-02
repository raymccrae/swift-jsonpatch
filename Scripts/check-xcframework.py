#!/usr/bin/env python3
"""Check that a built XCFramework contains the requested platform slices."""

import argparse
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("framework", type=Path)
parser.add_argument("platforms", nargs="+", choices=["ios", "macos", "tvos", "watchos"])
args = parser.parse_args()

with (args.framework / "Info.plist").open("rb") as stream:
    libraries = plistlib.load(stream)["AvailableLibraries"]

slices = set()
for library in libraries:
    platform = library["SupportedPlatform"]
    variant = library.get("SupportedPlatformVariant", "device")
    slices.add((platform, variant))
    directory = args.framework / library["LibraryIdentifier"]
    assert (directory / library["LibraryPath"]).is_dir(), library
    assert (directory / library["BinaryPath"]).is_file(), library
    assert library["SupportedArchitectures"], library

expected = {(platform, "device") for platform in args.platforms}
expected.update((platform, "simulator") for platform in args.platforms if platform != "macos")
missing = expected - slices
assert not missing, f"Missing XCFramework slices: {sorted(missing)}; found: {sorted(slices)}"
print(f"Validated XCFramework slices: {sorted(slices)}")
