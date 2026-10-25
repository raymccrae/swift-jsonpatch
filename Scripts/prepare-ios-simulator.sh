#!/bin/bash
# Provision a simulator for the selected Xcode; do not download usable runtimes again.
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-version)"

ensure_simulator() {
    xcrun simctl list --json | \
        python3 "$script_root/select-ios-simulator.py" "$simulator_sdk" --create-if-needed
}

if ensure_simulator; then
    exit 0
fi

# Xcode 16.2 supports -buildVersion but not -architectureVariant. Consult the
# selected tool rather than assuming the runner's Xcodes accept the same options.
download_args=(-downloadPlatform iOS -buildVersion "$simulator_sdk")
xcode_help="$(xcodebuild -help 2>&1)"
if [[ "$xcode_help" == *-architectureVariant* ]]; then
    download_args+=(-architectureVariant universal)
fi
# https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components
download_status=0
xcodebuild "${download_args[@]}" || download_status=$?

# Some Xcodes return a nonzero status for content already downloaded. Runtime
# availability, including a usable iPhone destination, is the success condition.
if ensure_simulator; then
    if [[ "$download_status" != 0 ]]; then
        echo "Runtime is available after xcodebuild returned $download_status." >&2
    fi
    exit 0
fi
echo "No usable iOS simulator after download (xcodebuild status $download_status)." >&2
exit 1
