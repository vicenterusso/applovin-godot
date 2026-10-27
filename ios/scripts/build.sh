#!/usr/bin/env bash
# Builds the iOS plugin binaries for one Godot version:
#   applovin_max.debug.xcframework    (linked into debug exports)
#   applovin_max.release.xcframework  (linked into release exports)
#
# Usage: ios/scripts/build.sh <godot_tag> [output_dir]
#   godot_tag   Godot git tag, e.g. 4.5.1-stable. Use the same Godot version you export with.
#   output_dir  default: ios/bin/<godot_tag>
#
# Environment:
#   APPLOVIN_IOS_SDK_VERSION  AppLovin iOS SDK used for the headers (default 13.6.4)
#   PLUGIN_VERSION            reported to AppLovin as "Godot-<version>" (default 1.0.0)
#   GODOT_DIR                 existing Godot checkout to use instead of cloning one
#
# Requirements: macOS with Xcode command line tools, git, python3 and scons.
set -euo pipefail

GODOT_TAG="${1:?usage: build.sh <godot_tag> [output_dir]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$IOS_DIR/build"
OUT_DIR="${2:-$IOS_DIR/bin/$GODOT_TAG}"
GODOT_DIR="${GODOT_DIR:-$BUILD_DIR/godot-$GODOT_TAG}"
SDK_VERSION="${APPLOVIN_IOS_SDK_VERSION:-13.6.4}"
PLUGIN_VERSION="${PLUGIN_VERSION:-1.0.0}"
SDK_DIR="$BUILD_DIR/applovin-sdk"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
FLAGS_PY="$SCRIPT_DIR/godot_flags.py"

mkdir -p "$BUILD_DIR" "$OUT_DIR"

# 1. Godot sources (headers + build flags).
if [ ! -d "$GODOT_DIR" ]; then
	git clone --depth 1 --branch "$GODOT_TAG" https://github.com/godotengine/godot.git "$GODOT_DIR"
fi

# 2. AppLovin SDK (headers only; the framework itself ships in the game export).
if [ "$(cat "$SDK_DIR/AppLovinSDK.version" 2>/dev/null || true)" != "$SDK_VERSION" ]; then
	"$SCRIPT_DIR/download_applovin_sdk.sh" "$SDK_VERSION" "$SDK_DIR"
fi
SDK_XCFRAMEWORK="$SDK_DIR/AppLovinSDK.xcframework"
SDK_DEVICE_SLICE="$(find "$SDK_XCFRAMEWORK" -mindepth 1 -maxdepth 1 -type d -name 'ios-*' ! -name '*simulator*' | head -n 1)"
SDK_SIMULATOR_SLICE="$(find "$SDK_XCFRAMEWORK" -mindepth 1 -maxdepth 1 -type d -name 'ios-*simulator' | head -n 1)"

build_slice() {
	local target="$1" arch="$2" simulator="$3"
	local name="$target.$arch.$([ "$simulator" = yes ] && echo simulator || echo device)"
	local db="$BUILD_DIR/compile_db/$GODOT_TAG/$name.json"
	local obj_dir="$BUILD_DIR/obj/$GODOT_TAG/$name"
	local sdk_slice="$SDK_DEVICE_SLICE"
	[ "$simulator" = yes ] && sdk_slice="$SDK_SIMULATOR_SLICE"

	echo "==> $name"
	mkdir -p "$(dirname "$db")" "$obj_dir"
	rm -f "$obj_dir"/*.o "$obj_dir"/*.a

	# Godot < 4.5 calls the simulator option "ios_simulator"; newer versions accept both.
	local scons_args=(platform=ios "target=$target" "arch=$arch" "simulator=$simulator" "ios_simulator=$simulator")

	(cd "$GODOT_DIR" && rm -f compile_commands.json && scons "${scons_args[@]}" compiledb=yes compile_commands.json >/dev/null)
	mv "$GODOT_DIR/compile_commands.json" "$db"

	# Generated headers (version, gdvirtual, ...) are produced by building a few engine objects.
	local objects=()
	while IFS= read -r line; do objects+=("$line"); done < <(python3 "$FLAGS_PY" objects "$db")
	(cd "$GODOT_DIR" && scons "${scons_args[@]}" "-j$JOBS" "${objects[@]}" >/dev/null)

	local flags=()
	while IFS= read -r line; do flags+=("$line"); done < <(python3 "$FLAGS_PY" flags "$db")
	local directory
	directory="$(python3 "$FLAGS_PY" directory "$db")"

	for source in "$IOS_DIR"/src/*.mm; do
		(cd "$directory" && xcrun clang++ "${flags[@]}" \
			-x objective-c++ -fobjc-arc \
			-F "$sdk_slice" -I "$IOS_DIR/src" \
			-DAPPLOVIN_MAX_PLUGIN_VERSION="\"$PLUGIN_VERSION\"" \
			-c "$source" -o "$obj_dir/$(basename "$source" .mm).o")
	done
	xcrun libtool -static -o "$obj_dir/libapplovin_max.a" "$obj_dir"/*.o 2>/dev/null
}

for target in template_debug template_release; do
	build_slice "$target" arm64 no
	build_slice "$target" arm64 yes
	build_slice "$target" x86_64 yes

	device_lib="$BUILD_DIR/obj/$GODOT_TAG/$target.arm64.device/libapplovin_max.a"
	simulator_dir="$BUILD_DIR/obj/$GODOT_TAG/$target.simulator"
	mkdir -p "$simulator_dir"
	xcrun lipo -create \
		"$BUILD_DIR/obj/$GODOT_TAG/$target.arm64.simulator/libapplovin_max.a" \
		"$BUILD_DIR/obj/$GODOT_TAG/$target.x86_64.simulator/libapplovin_max.a" \
		-output "$simulator_dir/libapplovin_max.a"

	xcframework="$OUT_DIR/applovin_max.${target#template_}.xcframework"
	rm -rf "$xcframework"
	xcodebuild -create-xcframework \
		-library "$device_lib" \
		-library "$simulator_dir/libapplovin_max.a" \
		-output "$xcframework"
done

cp "$IOS_DIR/plugin/applovin_max.gdip" "$OUT_DIR/"
echo "Done: $OUT_DIR"
