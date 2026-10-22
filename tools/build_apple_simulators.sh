#!/usr/bin/env bash
# Manual compile check only. No signing, export, upload or device installation. Includes pure-logic tests.
# Apple CI calls this from .github/workflows/apple-build.yml on macos-latest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH_PROJECT="$ROOT/PatrickFace.xcodeproj"
PHONE_WORKSPACE="$ROOT/iOSCompanion/PatrickFaceSuite.xcworkspace"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This check requires macOS with Xcode and Apple Simulator SDKs." >&2
  exit 1
fi
for tool in xcodebuild xcode-select xcrun python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool is unavailable: $tool" >&2
    exit 1
  fi
done

# Use the selected Xcode. Do not assume a version or install new runtimes.
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
xcrun --sdk watchsimulator --show-sdk-path
xcrun --sdk iphonesimulator --show-sdk-path

require_scheme() {
  local container_type="$1"
  local container_path="$2"
  local scheme="$3"
  xcodebuild "$container_type" "$container_path" -list -json |
    python3 -c '
import json
import sys
data = json.load(sys.stdin)
container = data.get("workspace", data.get("project", {}))
schemes = container.get("schemes", [])
expected = sys.argv[1]
print("Available schemes: " + ", ".join(schemes))
if expected not in schemes:
    sys.exit("Required shared scheme is missing: " + expected)
' "$scheme"
}

require_scheme -project "$WATCH_PROJECT" PatrickFace
require_scheme -workspace "$PHONE_WORKSPACE" PatrickCompanion

DERIVED_ROOT="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/patrick-simulator-build.XXXXXX")"
echo "Simulator build data: $DERIVED_ROOT"

xcrun swiftc "$ROOT/PatrickFace/PatrickShared.swift" "$ROOT/tools/NativeRulesChecks.swift" -o "$DERIVED_ROOT/native-rules"
"$DERIVED_ROOT/native-rules"
xcrun swiftc "$ROOT/PatrickFace/PatrickAnimationCatalog.swift" "$ROOT/PatrickFace/PatrickAnimationPolicy.swift" "$ROOT/tools/NativeAnimationChecks.swift" -o "$DERIVED_ROOT/native-animation"
"$DERIVED_ROOT/native-animation" "$ROOT/animation/catalog.json"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickExperience.swift" "$ROOT/tools/NativeExperienceChecks.swift" -o "$DERIVED_ROOT/native-experience"
"$DERIVED_ROOT/native-experience" "$ROOT/experience/themes.json" "$ROOT/experience/calendar.json"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickExperience.swift" "$ROOT/iOSCompanion/Shared/PatrickAutomation.swift" "$ROOT/iOSCompanion/Shared/PatrickModels.swift" "$ROOT/iOSCompanion/Shared/PatrickMessageSchema.swift" "$ROOT/tools/NativeAutomationChecks.swift" -o "$DERIVED_ROOT/native-automation"
"$DERIVED_ROOT/native-automation" "$ROOT/tools/fixtures/automation-events.json"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickHealthSummary.swift" "$ROOT/tools/NativeHealthChecks.swift" -o "$DERIVED_ROOT/native-health"
"$DERIVED_ROOT/native-health"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickHealthTrend.swift" "$ROOT/tools/NativeHealthTrendChecks.swift" -o "$DERIVED_ROOT/native-health-trend"
"$DERIVED_ROOT/native-health-trend" "$ROOT/ecosystem/health-trend-fixtures.json"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickHealthTrend.swift" "$ROOT/PatrickFace/PatrickHealthTrendAggregation.swift" "$ROOT/tools/NativeHealthTrendAggregationChecks.swift" -o "$DERIVED_ROOT/native-health-trend-aggregation"
"$DERIVED_ROOT/native-health-trend-aggregation"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickAftercare.swift" "$ROOT/tools/NativeAftercareChecks.swift" -o "$DERIVED_ROOT/native-aftercare"
"$DERIVED_ROOT/native-aftercare" "$ROOT/preview/aftercare-fixtures.json"

xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickWatchStatus.swift" "$ROOT/tools/NativeWatchStatusChecks.swift" -o "$DERIVED_ROOT/native-watch-status"
"$DERIVED_ROOT/native-watch-status"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickRoutineRun.swift" "$ROOT/tools/NativeRoutineRunChecks.swift" -o "$DERIVED_ROOT/native-routine-runs"
"$DERIVED_ROOT/native-routine-runs" "$ROOT/ecosystem/routine-run-fixtures.json"

xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickExperience.swift" "$ROOT/iOSCompanion/Shared/PatrickSettingsMerge.swift" "$ROOT/tools/NativeSettingsMergeChecks.swift" -o "$DERIVED_ROOT/native-settings-merge"
"$DERIVED_ROOT/native-settings-merge" "$ROOT/tools/fixtures/settings-merge.json"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickExperience.swift" "$ROOT/iOSCompanion/Shared/PatrickCountdownAlert.swift" "$ROOT/iOSCompanion/Shared/PatrickHapticPolicy.swift" "$ROOT/iOSCompanion/Shared/PatrickSpokenActions.swift" "$ROOT/iOSCompanion/Shared/PatrickDayPlan.swift" "$ROOT/iOSCompanion/Shared/PatrickWeekPlan.swift" "$ROOT/tools/NativeCountdownChecks.swift" -o "$DERIVED_ROOT/native-countdown"
"$DERIVED_ROOT/native-countdown"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickExperience.swift" "$ROOT/iOSCompanion/Shared/PatrickDayPlan.swift" "$ROOT/iOSCompanion/Shared/PatrickWeekPlan.swift" "$ROOT/tools/NativeDayPlanChecks.swift" -o "$DERIVED_ROOT/native-day-plan"
"$DERIVED_ROOT/native-day-plan"
xcrun swiftc "$ROOT/iOSCompanion/Shared/PatrickExperience.swift" "$ROOT/iOSCompanion/Shared/PatrickCountdownAlert.swift" "$ROOT/iOSCompanion/Shared/PatrickDayPlan.swift" "$ROOT/iOSCompanion/Shared/PatrickWeekPlan.swift" "$ROOT/tools/NativeWeekPlanChecks.swift" -o "$DERIVED_ROOT/native-week-plan"
"$DERIVED_ROOT/native-week-plan"


xcodebuild \
  -project "$WATCH_PROJECT" \
  -scheme PatrickFace \
  -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath "$DERIVED_ROOT/watch" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  build

xcodebuild \
  -workspace "$PHONE_WORKSPACE" \
  -scheme PatrickCompanion \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_ROOT/phone" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  build

python3 "$ROOT/tools/check_apple_bundle.py" "$DERIVED_ROOT/phone/Build/Products/Debug-iphonesimulator/PatrickCompanion.app"
PHONE_APP="$DERIVED_ROOT/phone/Build/Products/Debug-iphonesimulator/PatrickCompanion.app"
if [[ -d "$PHONE_APP/PlugIns/PatrickFieldTestNotification.appex" ]]; then
  echo "Field-test notification extension was embedded. The default build must leave it out." >&2
  exit 1
fi
FIELD_TEST_EXT="$DERIVED_ROOT/phone/Build/Products/Debug-iphonesimulator/PatrickFieldTestNotification.appex"
if [[ ! -d "$FIELD_TEST_EXT" ]]; then
  echo "Field-test notification extension did not compile." >&2
  exit 1
fi
# Compile once, then execute on an already installed simulator. Never download a runtime.
xcodebuild -workspace "$PHONE_WORKSPACE" -scheme PatrickCompanion -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED_ROOT/phone" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= build-for-testing

xcrun simctl list devices available -j > "$DERIVED_ROOT/test-simulators.json"
xcodebuild -workspace "$PHONE_WORKSPACE" -scheme PatrickCompanion -showdestinations \
  | tee "$DERIVED_ROOT/test-destinations.txt"
IOS_TEST_DEVICE_ID="$(python3 "$ROOT/tools/select_apple_simulator.py" \
  --devices "$DERIVED_ROOT/test-simulators.json" --destinations "$DERIVED_ROOT/test-destinations.txt")"
DIAGNOSTICS_ROOT="${RUNNER_TEMP:-$DERIVED_ROOT}/patrick-ci-logs"
mkdir -p "$DIAGNOSTICS_ROOT"
TEST_RESULTS="$DIAGNOSTICS_ROOT/contracts-$(basename "$DERIVED_ROOT").xcresult"
echo "XCTest result bundle: $TEST_RESULTS"
xcodebuild -workspace "$PHONE_WORKSPACE" -scheme PatrickCompanion -configuration Debug \
  -destination "platform=iOS Simulator,id=$IOS_TEST_DEVICE_ID" -destination-timeout 120 \
  -derivedDataPath "$DERIVED_ROOT/phone" -parallel-testing-enabled NO \
  -resultBundlePath "$TEST_RESULTS" test-without-building

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "PATRICK_PHONE_SIM_APP=$DERIVED_ROOT/phone/Build/Products/Debug-iphonesimulator/PatrickCompanion.app"
    echo "PATRICK_WATCH_SIM_APP=$DERIVED_ROOT/watch/Build/Products/Debug-watchsimulator/PatrickFace.app"
    echo "PATRICK_TEST_PHONE_UDID=$IOS_TEST_DEVICE_ID"
  } >> "$GITHUB_ENV"
fi

echo "Unsigned simulator builds, native pure-logic tests, XCTest execution and embedded bundle checks completed. No signed package was produced."
