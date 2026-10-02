#!/bin/bash
# Validate the standalone Xcode project. Build products stay outside the checkout.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_root="$(mktemp -d "${TMPDIR:-/tmp}/jsonpatch-apple.XXXXXX")"
cd "$repo_root"

run_build() {
    local name="$1"
    shift
    local log="$check_root/$name.log"
    if ! xcodebuild -project JSONPatch.xcodeproj -derivedDataPath "$check_root/DerivedData" \
        CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES "$@" >"$log" 2>&1; then
        cat "$log"
        return 1
    fi
    echo "$name passed ($log)"
}

case "${1:-}" in
    tests)
        run_build macos-tests -scheme JSONPatch -destination 'platform=macOS' test
        # Fail if the runner reports success without discovering Swift Testing tests.
        python3 - "$check_root/macos-tests.log" <<'CHECK'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert re.search(r'Test run with [1-9][0-9]* tests.*passed', text), text[-4000:]
CHECK
        simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator")
')"
        run_build ios-tests -scheme JSONPatch -destination "platform=iOS Simulator,id=$simulator_id" test
        python3 - "$check_root/ios-tests.log" <<'CHECK'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert re.search(r'Test run with [1-9][0-9]* tests.*passed', text), text[-4000:]
CHECK
        ;;
    frameworks)
        for sdk in macosx iphoneos iphonesimulator appletvos appletvsimulator watchos watchsimulator; do
            # SDK builds do not require an installed simulator runtime for the platform.
            scheme=JSONPatchFramework
            if [[ "$sdk" == macosx ]]; then scheme=JSONPatchMacFramework; fi
            run_build "$sdk" -scheme "$scheme" -configuration Release -sdk "$sdk" build
        done
        ;;
    *) echo "Usage: bash Scripts/check-apple.sh {tests|frameworks}" >&2; exit 2 ;;
esac
