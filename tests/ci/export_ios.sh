#!/usr/bin/env bash
# Exports tests/project as debug and release Xcode projects (export_project_only) with the
# Godot binary in $GODOT.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/tests/project"
: "${GODOT:?GODOT must point to the Godot editor binary}"

cd "$PROJECT"
"$GODOT" --headless --import

# Debug (simulator run + device link) and release (device link) Xcode projects.
for mode in debug release; do
	dir="$PROJECT/build/ios"
	[ "$mode" = release ] && dir="$PROJECT/build/ios-release"
	mkdir -p "$dir"
	"$GODOT" --headless "--export-$mode" "iOS" "$dir/AppLovinMaxTest.ipa" 2>&1 | tee "$dir/export.log"
	if grep -qiE "export for preset .* failed" "$dir/export.log"; then
		echo "Godot reported an export error ($mode)" >&2
		exit 1
	fi
	test -f "$dir/AppLovinMaxTest.xcodeproj/project.pbxproj"
done
