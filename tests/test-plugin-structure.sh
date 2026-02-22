#!/bin/bash
# test-plugin-structure.sh — Validates that all plugin components are present and well-formed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Plugin Structure ==="

# ── Plugin manifest ──────────────────────────────────────────────────────────

assert_file_exists "$PLUGIN_ROOT/.claude-plugin/plugin.json" "plugin.json exists"
assert_json_valid "$PLUGIN_ROOT/.claude-plugin/plugin.json" "plugin.json is valid JSON"
assert_json_field "$PLUGIN_ROOT/.claude-plugin/plugin.json" '.name' "plugin.json has name"
assert_json_field "$PLUGIN_ROOT/.claude-plugin/plugin.json" '.version' "plugin.json has version"
assert_json_field "$PLUGIN_ROOT/.claude-plugin/plugin.json" '.description' "plugin.json has description"

# ── Skill and agent files ────────────────────────────────────────────────────

assert_file_exists "$PLUGIN_ROOT/skills/analyze/SKILL.md" "SKILL.md exists"
assert_file_exists "$PLUGIN_ROOT/agents/era-researcher.md" "era-researcher agent exists"
assert_file_exists "$PLUGIN_ROOT/agents/narrative-synthesizer.md" "narrative-synthesizer agent exists"

# ── Template ─────────────────────────────────────────────────────────────────

assert_file_exists "$PLUGIN_ROOT/templates/timeline.html" "timeline.html template exists"

# ── Scripts ──────────────────────────────────────────────────────────────────

assert_file_exists "$PLUGIN_ROOT/scripts/detect-eras.sh" "detect-eras.sh exists"
assert_file_executable "$PLUGIN_ROOT/scripts/detect-eras.sh" "detect-eras.sh is executable"
assert_file_exists "$PLUGIN_ROOT/scripts/generate-timeline.sh" "generate-timeline.sh exists"
assert_file_executable "$PLUGIN_ROOT/scripts/generate-timeline.sh" "generate-timeline.sh is executable"

# ── Vendored TimelineJS3 ────────────────────────────────────────────────────

DIST="$PLUGIN_ROOT/node_modules/@knight-lab/timelinejs/dist"

assert_file_exists "$DIST/js/timeline.js" "TimelineJS3 timeline.js exists (source, renamed to .min.js during generation)"
assert_file_exists "$DIST/css/timeline.css" "TimelineJS3 timeline.css exists"
assert_dir_exists "$DIST/js/locale" "TimelineJS3 locale directory exists"
assert_dir_exists "$DIST/css/fonts" "TimelineJS3 fonts directory exists"

# Check font.default.css specifically (referenced by template)
if [ -f "$DIST/css/fonts/font.default.css" ]; then
    pass "font.default.css exists"
else
    skip "font.default.css not present (optional — generate-timeline.sh uses || true)"
fi

emit_results
