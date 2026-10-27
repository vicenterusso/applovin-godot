#!/usr/bin/env bash
# Checks the exported Xcode projects, links them for real devices (debug and release) and
# for the iOS Simulator against the official Godot template and AppLovinSDK.xcframework,
# runs the app in a simulator and waits for the on-device test result
# (tests/project/test_runner.gd).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPORT_DIR="$ROOT/tests/project/build/ios"
NAME="AppLovinMaxTest"
BUNDLE_ID="com.vicenterusso.applovinmaxtest"
TIMEOUT="${TEST_TIMEOUT:-900}"
fail=0

check() { # check <description> <command...>
	local description="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		echo "PASS  $description"
	else
		echo "FAIL  $description"
		fail=1
	fi
}

# 1. What the export plugin + .gdip put into the Xcode project.
PBXPROJ="$EXPORT_DIR/$NAME.xcodeproj/project.pbxproj"
PLIST="$(find "$EXPORT_DIR/$NAME" -maxdepth 1 -name "*-Info.plist" | head -n 1)"
check "Xcode project references AppLovinSDK.xcframework" grep -q "AppLovinSDK.xcframework" "$PBXPROJ"
check "Xcode project links the applovin_max plugin binary" grep -q "applovin_max.xcframework" "$PBXPROJ"
check "plugin init/deinit are registered" grep -rq "applovin_max_plugin_init" "$EXPORT_DIR/$NAME"
check "Xcode project has -ObjC linker flag" grep -q -- "-ObjC" "$PBXPROJ"
check "Xcode project weak-links AppTrackingTransparency" grep -q -- "-weak_framework,AppTrackingTransparency" "$PBXPROJ"
check "Info.plist has NSUserTrackingUsageDescription" grep -q "NSUserTrackingUsageDescription" "$PLIST"
check "Info.plist has SKAdNetworkItems" grep -q "SKAdNetworkItems" "$PLIST"
check "Info.plist has AppLovin SKAdNetwork ID" grep -q "ludvb6z3bs.skadnetwork" "$PLIST"
check "Info.plist has GADApplicationIdentifier" grep -q "ca-app-pub-3940256099942544~1458002511" "$PLIST"
plutil -lint "$PLIST"

# 2. Simulator.
UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
')"
echo "Simulator: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# 3. Link for real devices, debug and release (this is where an engine ABI mismatch shows
#    up as "Undefined symbols for architecture arm64").
xcode_build() { # xcode_build <export_dir> <configuration> <log name> <xcodebuild args...>
	local dir="$1" configuration="$2" log="$1/$3"
	shift 3
	xcodebuild -project "$dir/$NAME.xcodeproj" -scheme "$NAME" -configuration "$configuration" \
		-derivedDataPath "$dir/DerivedData" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
		"$@" build > "$log" 2>&1 || true
	grep -E "error:|Undefined symbols|BUILD (SUCCEEDED|FAILED)" "$log" | head -n 40 || true
	if grep -q "BUILD SUCCEEDED" "$log"; then
		echo "PASS  xcodebuild $configuration ($*)"
	else
		echo "FAIL  xcodebuild $configuration ($*)"
		tail -n 60 "$log"
		return 1
	fi
}
xcode_build "$EXPORT_DIR" Debug xcodebuild-device-debug.log -sdk iphoneos -destination "generic/platform=iOS" || fail=1
xcode_build "$ROOT/tests/project/build/ios-release" Release xcodebuild-device-release.log -sdk iphoneos -destination "generic/platform=iOS" || fail=1
cp "$ROOT/tests/project/build/ios-release/xcodebuild-device-release.log" "$EXPORT_DIR/" 2>/dev/null || true

# 4. Simulator build. Godot 4.4+ templates weak-link MetalFX, which the iOS Simulator SDK
#    does not ship (the simulator renderer does not use Metal), so drop that one flag.
sed -i '' 's/ -weak_framework MetalFX//g' "$PBXPROJ"
xcode_build "$EXPORT_DIR" Debug xcodebuild.log -sdk iphonesimulator -destination "id=$UDID" ONLY_ACTIVE_ARCH=YES || exit 1
DERIVED="$EXPORT_DIR/DerivedData"

APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -name "$NAME.app" | head -n 1)"
check "AppLovinSDK.framework is embedded in the app" test -d "$APP/Frameworks/AppLovinSDK.framework"
check "AppLovin resources bundle is in the app" test -d "$APP/Frameworks/AppLovinSDK.framework/AppLovinSDKResources.bundle"

# 5. Run the on-device test.
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch --terminate-running-process \
	--stdout="$EXPORT_DIR/app_stdout.log" --stderr="$EXPORT_DIR/app_stderr.log" "$UDID" "$BUNDLE_ID"

start=$(date +%s)
RESULT=""
while true; do
	DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
	if [ -n "$DATA" ]; then
		RESULT="$(find "$DATA" -name applovin_test_result.txt 2>/dev/null | head -n 1)"
	fi
	if [ -n "$RESULT" ] && grep -q "\[ALTEST\] RESULT" "$RESULT"; then
		break
	fi
	if [ $(( $(date +%s) - start )) -gt "$TIMEOUT" ]; then
		echo "Timed out waiting for the test result" >&2
		break
	fi
	sleep 5
done

echo "----- test output -----"
if [ -n "$RESULT" ]; then
	cp "$RESULT" "$EXPORT_DIR/applovin_test_result.txt"
	cat "$RESULT"
else
	echo "(no result file)"
	tail -n 100 "$EXPORT_DIR/app_stdout.log" "$EXPORT_DIR/app_stderr.log" 2>/dev/null || true
fi
echo "----- script / binding errors -----"
if grep -E "SCRIPT ERROR|Invalid call|Nonexistent function" "$EXPORT_DIR/app_stdout.log" "$EXPORT_DIR/app_stderr.log" 2>/dev/null; then
	echo "Godot reported script or binding errors" >&2
	fail=1
else
	echo "(none)"
fi

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
[ -n "$RESULT" ] && grep -q "\[ALTEST\] RESULT PASS" "$RESULT" || fail=1
exit $fail
