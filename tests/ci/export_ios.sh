#!/usr/bin/env bash
# Exports tests/project as an Xcode project (export_project_only) with the Godot binary in $GODOT.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/tests/project"
: "${GODOT:?GODOT must point to the Godot editor binary}"

mkdir -p "$PROJECT/build/ios"
cd "$PROJECT"
"$GODOT" --headless --import
"$GODOT" --headless --export-debug "iOS" "$PROJECT/build/ios/AppLovinMaxTest.ipa" 2>&1 | tee "$PROJECT/build/ios/export.log"
if grep -qiE "export for preset .* failed" "$PROJECT/build/ios/export.log"; then
	echo "Godot reported an export error" >&2
	exit 1
fi
test -f "$PROJECT/build/ios/AppLovinMaxTest.xcodeproj/project.pbxproj"
