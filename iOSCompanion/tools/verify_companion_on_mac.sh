#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_ROOT/.." && pwd)"
WORKSPACE="$IOS_ROOT/PatrickFaceSuite.xcworkspace"
WATCH_PROJECT="$REPO_ROOT/PatrickFace.xcodeproj"
DERIVED_DATA="${PATRICK_DERIVED_DATA:-}"
if [ -z "$DERIVED_DATA" ]; then
  DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/patrick-companion.XXXXXX")"
fi

IOS_BUNDLE_ID="com.chans.patrickface.companion"
WIDGET_BUNDLE_ID="$IOS_BUNDLE_ID.widgets"
WATCH_BUNDLE_ID="$IOS_BUNDLE_ID.watchkitapp"
COMPLICATION_BUNDLE_ID="$WATCH_BUNDLE_ID.complications"
APP_GROUP="group.com.chans.patrickface.shared"

command -v xcodebuild >/dev/null
command -v xcrun >/dev/null
command -v plutil >/dev/null
command -v python3 >/dev/null

python3 "$REPO_ROOT/tools/validate_watch_project.py"
python3 "$IOS_ROOT/tools/validate_structure.py"

plutil -lint \
  "$REPO_ROOT/PatrickFace/Info.plist" \
  "$REPO_ROOT/PatrickFace/PatrickFace.entitlements" \
  "$REPO_ROOT/PatrickFace/PrivacyInfo.xcprivacy" \
  "$REPO_ROOT/PatrickFaceComplications/Info.plist" \
  "$REPO_ROOT/PatrickFaceComplications/PatrickFaceComplications.entitlements" \
  "$IOS_ROOT/PatrickCompanion/Info.plist" \
  "$IOS_ROOT/PatrickCompanion/PatrickCompanion.entitlements" \
  "$IOS_ROOT/PatrickWidgets/Info.plist" \
  "$IOS_ROOT/PatrickWidgets/PatrickWidgets.entitlements" \
  "$IOS_ROOT/Resources/PrivacyInfo.xcprivacy"

python3 -c '
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    payload = plistlib.load(stream)
assert payload.get("WKCompanionAppBundleIdentifier") == sys.argv[2]
assert payload.get("WKWatchOnly") is False
assert payload.get("WKRunsIndependentlyOfCompanionApp") is True
' "$REPO_ROOT/PatrickFace/Info.plist" "$IOS_BUNDLE_ID"

for entitlement in \
  "$REPO_ROOT/PatrickFace/PatrickFace.entitlements" \
  "$REPO_ROOT/PatrickFaceComplications/PatrickFaceComplications.entitlements" \
  "$IOS_ROOT/PatrickCompanion/PatrickCompanion.entitlements" \
  "$IOS_ROOT/PatrickWidgets/PatrickWidgets.entitlements"
do
  python3 -c '
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    payload = plistlib.load(stream)
assert payload.get("com.apple.security.application-groups") == [sys.argv[2]]
' "$entitlement" "$APP_GROUP"
done

xcodebuild -list -workspace "$WORKSPACE"
xcodebuild -list -project "$WATCH_PROJECT"

xcodebuild \
  -project "$WATCH_PROJECT" \
  -scheme PatrickFace \
  -configuration Debug \
  -destination "generic/platform=watchOS Simulator" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme PatrickCompanion \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

IOS_APP="$(find "$DERIVED_DATA/Build/Products" \
  -type d -path "*/PatrickCompanion.app" -print -quit)"
test -n "$IOS_APP"
test "$(plutil -extract CFBundleIdentifier raw "$IOS_APP/Info.plist")" \
  = "$IOS_BUNDLE_ID"

WIDGET="$IOS_APP/PlugIns/PatrickWidgets.appex"
WATCH_APP="$IOS_APP/Watch/PatrickFace.app"
COMPLICATION="$WATCH_APP/PlugIns/PatrickFaceComplications.appex"
test -d "$WIDGET"
test -d "$WATCH_APP"
test -d "$COMPLICATION"
test "$(plutil -extract CFBundleIdentifier raw "$WIDGET/Info.plist")" \
  = "$WIDGET_BUNDLE_ID"
test "$(plutil -extract CFBundleIdentifier raw "$WATCH_APP/Info.plist")" \
  = "$WATCH_BUNDLE_ID"
test "$(plutil -extract CFBundleIdentifier raw "$COMPLICATION/Info.plist")" \
  = "$COMPLICATION_BUNDLE_ID"
test "$(plutil -extract WKCompanionAppBundleIdentifier raw \
  "$WATCH_APP/Info.plist")" = "$IOS_BUNDLE_ID"

IOS_TEST_DEVICE_ID="${IOS_TEST_DEVICE_ID:-}"
if [ -z "$IOS_TEST_DEVICE_ID" ]; then
  IOS_TEST_DEVICE_ID="$(xcrun simctl list devices available -j | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
for runtime in sorted(payload.get("devices", {}), reverse=True):
    devices = payload["devices"][runtime]
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator; install one or set IOS_TEST_DEVICE_ID.")
')"
fi

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme PatrickCompanion \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$IOS_TEST_DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  test

cat <<EOF
PASS: source gates, plists, both simulator builds, embedded products, bundle
hierarchy, and iPhone contract tests completed.
Derived data was written to: $DERIVED_DATA

Still requires a signed physical iPhone/Apple Watch pair:
1. Register all four bundle IDs and the App Group in the Developer portal.
2. Select one Team on all app/extension targets and refresh profiles.
3. Install from the PatrickCompanion scheme; confirm watch auto-install/pairing.
4. Exercise reachable, suspended, offline, application-context, and queued paths.
5. Confirm theme, sleep, preview, timer, deduplication, and acknowledgements.
6. Archive with signing, Validate App, and inspect the Organizer distribution log.
EOF
