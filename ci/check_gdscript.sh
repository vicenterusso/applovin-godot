#!/usr/bin/env bash
# Loads the addon in a headless Godot editor (parses every script, runs the editor
# plugin) and runs the desktop smoke test. Usage: ci/check_gdscript.sh <godot_binary>
set -euo pipefail

GODOT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$(mktemp -d)"
trap 'rm -rf "$PROJECT"' EXIT

cp -R "$ROOT/addons" "$PROJECT/"
cp "$ROOT/ci/smoke_test.gd" "$PROJECT/"
cat > "$PROJECT/project.godot" <<'PROJECT_EOF'
config_version=5

[application]
config/name="AppLovinMaxCI"

[autoload]
AppLovinMax="*res://addons/applovin_max/applovin_max.gd"

[editor_plugins]
enabled=PackedStringArray("res://addons/applovin_max/plugin.cfg")
PROJECT_EOF

check_log() {
	if grep -E "SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource" "$1"; then
		echo "GDScript errors found" >&2
		exit 1
	fi
}

echo "==> Editor load"
"$GODOT" --headless --editor --quit --path "$PROJECT" 2>&1 | tee "$PROJECT/editor.log"
check_log "$PROJECT/editor.log"

echo "==> Smoke test"
"$GODOT" --headless --path "$PROJECT" -s res://smoke_test.gd 2>&1 | tee "$PROJECT/smoke.log"
check_log "$PROJECT/smoke.log"
grep -q "SMOKE TEST OK" "$PROJECT/smoke.log"
