#!/usr/bin/env bash
# Installs the test APK on the running emulator/device, launches it and waits for the
# on-device test (tests/project/test_runner.gd) to report its result through logcat.
set -euo pipefail

APK="${1:?apk}"
PACKAGE="com.vicenterusso.applovinmaxtest"
LOG_DIR="${2:-$(dirname "$APK")}"
TIMEOUT="${TEST_TIMEOUT:-900}"

diagnostics() {
	echo "----- crash buffer -----"
	adb logcat -d -b crash 2>/dev/null | tail -n 120 || true
	echo "----- app / runtime log (last 250 lines) -----"
	adb logcat -d 2>/dev/null | grep -E "$PACKAGE|AndroidRuntime|FATAL|DEBUG +:|libc +:|godot|GodotAppLovinMax|AppLovin|ActivityManager: (Start|Process)" | tail -n 250 || true
}

adb wait-for-device
adb install -r -g "$APK"
adb logcat -c

ACTIVITY="$(adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$PACKAGE" | tr -d '\r' | tail -n 1)"
echo "Launcher activity: $ACTIVITY"
adb shell am start -W -n "$ACTIVITY"

start=$(date +%s)
seen_running=0
while true; do
	adb logcat -d -s godot:V > "$LOG_DIR/godot_logcat.txt" || true
	if grep -q "\[ALTEST\] RESULT" "$LOG_DIR/godot_logcat.txt"; then
		break
	fi
	elapsed=$(( $(date +%s) - start ))
	if [ "$elapsed" -gt "$TIMEOUT" ]; then
		echo "Timed out waiting for the test result" >&2
		break
	fi
	if adb shell pidof "$PACKAGE" >/dev/null 2>&1; then
		seen_running=1
	elif [ "$seen_running" = 1 ] || [ "$elapsed" -gt 60 ]; then
		echo "The test app is not running anymore (crash?)" >&2
		sleep 3
		adb logcat -d -s godot:V > "$LOG_DIR/godot_logcat.txt" || true
		break
	fi
	sleep 5
done

adb logcat -d > "$LOG_DIR/full_logcat.txt" || true
adb exec-out screencap -p > "$LOG_DIR/screen.png" 2>/dev/null || true
echo "----- test output -----"
grep "\[ALTEST\]" "$LOG_DIR/godot_logcat.txt" | sed 's/.*\[ALTEST\]/[ALTEST]/' || true

if ! grep -q "\[ALTEST\] RESULT PASS" "$LOG_DIR/godot_logcat.txt"; then
	diagnostics
	exit 1
fi
echo "----- script / binding errors -----"
if grep -E "SCRIPT ERROR|Invalid call|Nonexistent function|jni_singleton" "$LOG_DIR/godot_logcat.txt"; then
	echo "Godot reported script or binding errors" >&2
	exit 1
fi
echo "(none)"
