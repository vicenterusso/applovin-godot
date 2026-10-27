#!/usr/bin/env bash
# Installs the test APK on the running emulator/device, launches it and waits for the
# on-device test (tests/project/test_runner.gd) to report its result through logcat.
set -euo pipefail

APK="${1:?apk}"
PACKAGE="com.vicenterusso.applovinmaxtest"
LOG_DIR="${2:-$(dirname "$APK")}"
TIMEOUT="${TEST_TIMEOUT:-900}"

adb wait-for-device
adb install -r -g "$APK"
adb logcat -c
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null

start=$(date +%s)
while true; do
	adb logcat -d -s godot:V > "$LOG_DIR/godot_logcat.txt" || true
	if grep -q "\[ALTEST\] RESULT" "$LOG_DIR/godot_logcat.txt"; then
		break
	fi
	if [ $(( $(date +%s) - start )) -gt "$TIMEOUT" ]; then
		echo "Timed out waiting for the test result" >&2
		break
	fi
	if ! adb shell pidof "$PACKAGE" >/dev/null 2>&1 && [ $(( $(date +%s) - start )) -gt 30 ]; then
		echo "The test app is not running anymore (crash?)" >&2
		sleep 3
		adb logcat -d -s godot:V > "$LOG_DIR/godot_logcat.txt" || true
		break
	fi
	sleep 5
done

adb logcat -d > "$LOG_DIR/full_logcat.txt" || true
echo "----- test output -----"
grep "\[ALTEST\]" "$LOG_DIR/godot_logcat.txt" | sed 's/.*\[ALTEST\]/[ALTEST]/' || true
echo "----- script / binding errors -----"
if grep -E "SCRIPT ERROR|Invalid call|Nonexistent function|jni_singleton" "$LOG_DIR/godot_logcat.txt"; then
	echo "Godot reported script or binding errors" >&2
	exit 1
fi
echo "(none)"
grep -q "\[ALTEST\] RESULT PASS" "$LOG_DIR/godot_logcat.txt"
