#!/usr/bin/env bash
# Fills tests/project with the addon under test and writes res://test_config.json.
#
# Usage: tests/prepare_project.sh [ios_plugin_dir]
#   ios_plugin_dir  folder with applovin_max.gdip + applovin_max.{debug,release}.xcframework
#
# Optional environment (e.g. from repository secrets) to test with a real AppLovin account:
#   APPLOVIN_SDK_KEY, APPLOVIN_TEST_DEVICE_IDS (comma separated),
#   APPLOVIN_{ANDROID,IOS}_{INTERSTITIAL,REWARDED,APP_OPEN,BANNER,MREC}_ID
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/tests/project"

rm -rf "$PROJECT/addons/applovin_max"
cp -R "$ROOT/addons/applovin_max" "$PROJECT/addons/"

if [ -n "${1:-}" ]; then
	rm -rf "$PROJECT/ios/plugins/applovin_max"
	mkdir -p "$PROJECT/ios/plugins/applovin_max"
	cp -R "$1"/. "$PROJECT/ios/plugins/applovin_max/"
fi

python3 - "$PROJECT/test_config.json" <<'PY'
import json, os, sys

# Placeholder key with the shape of a real one; AppLovin rejects it, so ad requests
# end in ad_load_failed, which still exercises every native callback.
placeholder_key = "CI" + "x" * 84

def ids(platform):
    result = {}
    for kind in ("interstitial", "rewarded", "app_open", "banner", "mrec"):
        value = os.environ.get(f"APPLOVIN_{platform.upper()}_{kind.upper()}_ID", "").strip()
        result[kind] = value or f"ci{platform}{kind}".ljust(16, "0")[:16]
    return result

config = {
    "sdk_key": os.environ.get("APPLOVIN_SDK_KEY", "").strip() or placeholder_key,
    "test_device_advertising_ids": [
        i.strip() for i in os.environ.get("APPLOVIN_TEST_DEVICE_IDS", "").split(",") if i.strip()
    ],
    "android": ids("android"),
    "ios": ids("ios"),
}
with open(sys.argv[1], "w") as f:
    json.dump(config, f, indent=2)
print("test_config.json written (real SDK key: %s)" % ("yes" if os.environ.get("APPLOVIN_SDK_KEY") else "no"))
PY
