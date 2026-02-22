#!/bin/bash
# test-integration.sh — End-to-end: detect-eras -> synthetic data -> generate-timeline

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

DETECT="$PLUGIN_ROOT/scripts/detect-eras.sh"
GENERATE="$PLUGIN_ROOT/scripts/generate-timeline.sh"

echo "=== Integration ==="

# ── Create realistic repo ───────────────────────────────────────────────────

echo "  Creating realistic repo (30 commits, 3 tags, 3 contributors)..."
REPO=$(create_test_repo 30 "8:v1.0,18:v2.0,25:v3.0" 3)

# ── Phase 1: detect-eras ────────────────────────────────────────────────────

ERA_FILE=$(make_temp_dir)/eras.json
"$DETECT" "$REPO" > "$ERA_FILE"

assert_json_valid "$ERA_FILE" "detect-eras output is valid JSON"
assert_json_array_min_length "$ERA_FILE" 1 "detect-eras found at least 1 era"

ERA_COUNT=$(jq 'length' "$ERA_FILE")
echo "  Detected $ERA_COUNT eras"

# ── Phase 2: build synthetic TimelineJS3 JSON from era output ────────────────

TIMELINE_JSON=$(make_temp_dir)/timeline-data.json
jq '{
    title: {
        text: {
            headline: "Integration Test Timeline",
            text: "Auto-generated from era data"
        }
    },
    events: [.[] | {
        start_date: {
            year: (.start_date | split("-")[0]),
            month: (.start_date | split("-")[1]),
            day: (.start_date | split("-")[2])
        },
        end_date: {
            year: (.end_date | split("-")[0]),
            month: (.end_date | split("-")[1]),
            day: (.end_date | split("-")[2])
        },
        text: {
            headline: .name,
            text: "\(.commit_count) commits by \(.contributor_count) contributors"
        }
    }]
}' "$ERA_FILE" > "$TIMELINE_JSON"

assert_json_valid "$TIMELINE_JSON" "synthetic TimelineJS3 JSON is valid"

EVENT_COUNT=$(jq '.events | length' "$TIMELINE_JSON")
assert_equals "$ERA_COUNT" "$EVENT_COUNT" "event count matches era count (data round-trip)"

# ── Phase 3: generate-timeline ──────────────────────────────────────────────

OUTPUT_DIR=$(make_temp_dir)/integration-output
"$GENERATE" "$TIMELINE_JSON" "$OUTPUT_DIR" "$PLUGIN_ROOT" > /dev/null

assert_file_exists "$OUTPUT_DIR/index.html" "integration: index.html created"
assert_file_exists "$OUTPUT_DIR/timeline-data.json" "integration: timeline-data.json created"
assert_file_exists "$OUTPUT_DIR/timeline-data.js" "integration: timeline-data.js created"
assert_file_exists "$OUTPUT_DIR/assets/js/timeline.min.js" "integration: timeline.min.js created"
assert_file_exists "$OUTPUT_DIR/assets/css/timeline.css" "integration: timeline.css created"

# Verify the round-trip preserved event count in the output
OUTPUT_EVENT_COUNT=$(jq '.events | length' "$OUTPUT_DIR/timeline-data.json")
assert_equals "$ERA_COUNT" "$OUTPUT_EVENT_COUNT" "output JSON event count matches era count"

emit_results
