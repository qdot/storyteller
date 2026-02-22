#!/bin/bash
# test-template.sh — Validates timeline.html template content.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

TEMPLATE="$PLUGIN_ROOT/templates/timeline.html"

echo "=== Template Validation ==="

# ── Basic HTML structure ─────────────────────────────────────────────────────

assert_contains "$TEMPLATE" "<!DOCTYPE html>" "has DOCTYPE"
assert_contains "$TEMPLATE" "<html" "has html tag"
assert_contains "$TEMPLATE" "timeline-embed" "has timeline-embed div"

# ── Asset references ─────────────────────────────────────────────────────────

assert_contains "$TEMPLATE" "assets/js/timeline.min.js" "references timeline.min.js"
assert_contains "$TEMPLATE" "assets/css/timeline.css" "references timeline.css"
assert_contains "$TEMPLATE" "assets/css/fonts/font.default.css" "references font.default.css"
assert_contains "$TEMPLATE" "timeline-data.json" "references timeline-data.json"

# ── TimelineJS3 initialization ───────────────────────────────────────────────

assert_contains "$TEMPLATE" "TL.Timeline" "uses TL.Timeline constructor"

emit_results
