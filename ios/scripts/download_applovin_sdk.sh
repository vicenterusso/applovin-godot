#!/usr/bin/env bash
# Downloads the official AppLovin iOS SDK (AppLovinSDK.xcframework).
#
# Usage: ios/scripts/download_applovin_sdk.sh [version] [destination_dir]
#   version          AppLovin iOS SDK version (default: 13.6.4)
#   destination_dir  where AppLovinSDK.xcframework is placed (default: ios/build/applovin-sdk)
set -euo pipefail

VERSION="${1:-13.6.4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${2:-$SCRIPT_DIR/../build/applovin-sdk}"
URL="https://artifacts.applovin.com/ios/com/applovin/applovin-sdk/applovin-ios-sdk-${VERSION}.zip"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading AppLovin iOS SDK ${VERSION}..."
curl -fsSL --retry 3 -o "$TMP/sdk.zip" "$URL"
unzip -q "$TMP/sdk.zip" -d "$TMP/sdk"

FRAMEWORK="$(find "$TMP/sdk" -maxdepth 3 -type d -name AppLovinSDK.xcframework | head -n 1)"
if [ -z "$FRAMEWORK" ]; then
	echo "error: AppLovinSDK.xcframework not found in $URL" >&2
	exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/AppLovinSDK.xcframework"
cp -R "$FRAMEWORK" "$DEST/"
echo "$VERSION" > "$DEST/AppLovinSDK.version"
echo "AppLovinSDK.xcframework ${VERSION} -> $DEST"
