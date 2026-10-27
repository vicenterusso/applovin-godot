#!/usr/bin/env bash
# Installs an official Godot editor and the export templates needed for one platform.
#
# Usage: tests/ci/install_godot.sh <linux|macos> <godot_tag> <template_file>...
#   e.g. tests/ci/install_godot.sh linux 4.3-stable android_source.zip
# Writes GODOT=<editor binary> to $GITHUB_ENV (or prints it).
# Downloads are kept in $GODOT_CI_CACHE (default: ~/.cache/godot-ci) so CI can cache them.
set -euo pipefail

OS_NAME="${1:?os}"
TAG="${2:?godot tag}"
shift 2
CACHE="${GODOT_CI_CACHE:-$HOME/.cache/godot-ci}/$TAG"
BASE_URL="https://github.com/godotengine/godot/releases/download/$TAG"
mkdir -p "$CACHE"

download() {
	local url="$1" out="$2"
	[ -s "$out" ] && return 0
	echo "Downloading $url"
	curl -fL --retry 3 --retry-delay 5 -o "$out.part" "$url"
	mv "$out.part" "$out"
}

# Editor.
case "$OS_NAME" in
	linux)
		download "$BASE_URL/Godot_v${TAG}_linux.x86_64.zip" "$CACHE/editor.zip"
		[ -x "$CACHE/editor/godot" ] || {
			rm -rf "$CACHE/editor" && mkdir -p "$CACHE/editor"
			unzip -q "$CACHE/editor.zip" -d "$CACHE/editor"
			mv "$CACHE"/editor/Godot_v*_linux.x86_64 "$CACHE/editor/godot"
		}
		GODOT="$CACHE/editor/godot"
		TEMPLATES_ROOT="$HOME/.local/share/godot/export_templates"
		;;
	macos)
		download "$BASE_URL/Godot_v${TAG}_macos.universal.zip" "$CACHE/editor.zip"
		[ -x "$CACHE/editor/Godot.app/Contents/MacOS/Godot" ] || {
			rm -rf "$CACHE/editor" && mkdir -p "$CACHE/editor"
			ditto -x -k "$CACHE/editor.zip" "$CACHE/editor"
		}
		GODOT="$CACHE/editor/Godot.app/Contents/MacOS/Godot"
		TEMPLATES_ROOT="$HOME/Library/Application Support/Godot/export_templates"
		;;
	*)
		echo "unknown os: $OS_NAME" >&2
		exit 1
		;;
esac

# Export templates (only the files that are needed; the full .tpz is >1 GB).
TEMPLATES_CACHE="$CACHE/templates"
mkdir -p "$TEMPLATES_CACHE"
missing=0
for file in version.txt "$@"; do
	[ -s "$TEMPLATES_CACHE/$file" ] || missing=1
done
if [ "$missing" = 1 ]; then
	download "$BASE_URL/Godot_v${TAG}_export_templates.tpz" "$CACHE/templates.tpz"
	members=()
	for file in version.txt "$@"; do members+=("templates/$file"); done
	unzip -o -j "$CACHE/templates.tpz" "${members[@]}" -d "$TEMPLATES_CACHE"
	rm -f "$CACHE/templates.tpz"
fi
VERSION="$(tr -d '[:space:]' < "$TEMPLATES_CACHE/version.txt")"
mkdir -p "$TEMPLATES_ROOT/$VERSION"
cp "$TEMPLATES_CACHE"/* "$TEMPLATES_ROOT/$VERSION/"
echo "Templates $VERSION -> $TEMPLATES_ROOT/$VERSION: $(ls "$TEMPLATES_ROOT/$VERSION" | tr '\n' ' ')"

"$GODOT" --version
if [ -n "${GITHUB_ENV:-}" ]; then
	echo "GODOT=$GODOT" >> "$GITHUB_ENV"
else
	echo "GODOT=$GODOT"
fi
