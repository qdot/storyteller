#!/bin/bash
# test-generate-timeline.sh — Unit tests for generate-timeline.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

GENERATE="$PLUGIN_ROOT/scripts/generate-timeline.sh"
FIXTURE="$SCRIPT_DIR/fixtures/minimal-timeline.json"

echo "=== Generate Timeline ==="

# ── Error handling ───────────────────────────────────────────────────────────

# No args → non-zero exit (uses ${1:?...} which exits 2)
assert_exit_code nonzero "exits non-zero with no args" "$GENERATE"

# Missing data file → non-zero exit
TMPOUT=$(make_temp_dir)
assert_exit_code nonzero "exits non-zero for missing data file" \
    "$GENERATE" "/nonexistent/data.json" "$TMPOUT/out" "$PLUGIN_ROOT"

# Invalid JSON → non-zero exit
INVALID_JSON=$(make_temp_dir)/bad.json
echo "not json" > "$INVALID_JSON"
TMPOUT2=$(make_temp_dir)
assert_exit_code nonzero "exits non-zero for invalid JSON" \
    "$GENERATE" "$INVALID_JSON" "$TMPOUT2/out" "$PLUGIN_ROOT"

# ── Successful generation ───────────────────────────────────────────────────

echo "  Running generate-timeline.sh with fixture..."
OUTPUT_DIR=$(make_temp_dir)/timeline-output
"$GENERATE" "$FIXTURE" "$OUTPUT_DIR" "$PLUGIN_ROOT" > /dev/null

assert_file_exists "$OUTPUT_DIR/index.html" "output: index.html created"
assert_file_exists "$OUTPUT_DIR/timeline-data.json" "output: timeline-data.json created"
assert_file_exists "$OUTPUT_DIR/timeline-data.js" "output: timeline-data.js created"
assert_file_exists "$OUTPUT_DIR/assets/js/timeline.min.js" "output: timeline.min.js created"
assert_file_exists "$OUTPUT_DIR/assets/css/timeline.css" "output: timeline.css created"
assert_dir_exists "$OUTPUT_DIR/assets/js/locale" "output: locale directory created"

# Verify timeline-data.js contains the window assignment
assert_contains "$OUTPUT_DIR/timeline-data.js" "window.defined_timeline_data" \
    "timeline-data.js contains window.defined_timeline_data"

# Verify copied JSON is valid
assert_json_valid "$OUTPUT_DIR/timeline-data.json" "copied timeline-data.json is valid JSON"

# Verify fonts dir was created (even if empty — script uses || true)
assert_dir_exists "$OUTPUT_DIR/assets/css/fonts" "output: fonts directory created"

emit_results
