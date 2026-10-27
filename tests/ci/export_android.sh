#!/usr/bin/env bash
# Exports tests/project as a debug APK (Gradle build) with the Godot binary in $GODOT,
# then checks the merged manifest for the plugin, the AppLovin SDK and the AdMob app ID.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/tests/project"
APK="$PROJECT/build/android/applovin_max_test.apk"
: "${GODOT:?GODOT must point to the Godot editor binary}"

KEYSTORE="${RUNNER_TEMP:-/tmp}/applovin-ci-debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
	keytool -genkeypair -v -keystore "$KEYSTORE" -storepass android -keypass android \
		-alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

mkdir -p "$(dirname "$APK")"
rm -f "$APK"
cd "$PROJECT"
"$GODOT" --headless --import
"$GODOT" --headless --install-android-build-template --export-debug "Android" "$APK" 2>&1 | tee "$PROJECT/build/android/export.log"
if grep -qiE "export for preset .* failed" "$PROJECT/build/android/export.log"; then
	echo "Godot reported an export error" >&2
	exit 1
fi
test -f "$APK" || { echo "APK was not produced" >&2; exit 1; }
ls -la "$APK"

AAPT2="$(ls -d "$ANDROID_HOME"/build-tools/*/aapt2 | sort -V | tail -n 1)"
"$AAPT2" dump xmltree --file AndroidManifest.xml "$APK" > "$PROJECT/build/android/manifest.txt"
fail=0
for expected in \
	"org.godotengine.plugin.v2.GodotAppLovinMax" \
	"com.vicenterusso.godot.applovinmax.GodotAppLovinMax" \
	"com.applovin.adview.AppLovinFullscreenActivity" \
	"com.applovin.sdk.AppLovinInitProvider" \
	"com.google.android.gms.ads.APPLICATION_ID" \
	"ca-app-pub-3940256099942544~3347511713"; do
	if grep -q "$expected" "$PROJECT/build/android/manifest.txt"; then
		echo "PASS  manifest contains $expected"
	else
		echo "FAIL  manifest is missing $expected"
		fail=1
	fi
done
exit $fail
