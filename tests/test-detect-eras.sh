#!/bin/bash
# test-detect-eras.sh — Unit tests for detect-eras.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

DETECT="$PLUGIN_ROOT/scripts/detect-eras.sh"

echo "=== Detect Eras ==="

# ── Error handling ───────────────────────────────────────────────────────────

# Non-repo path should exit non-zero
NOT_REPO=$(make_temp_dir)
assert_exit_code nonzero "exits non-zero for non-repo path" "$DETECT" "$NOT_REPO"

# ── Tagged repo (20 commits, 3 tags) ────────────────────────────────────────

echo "  Setting up tagged repo (20 commits, 3 tags)..."
TAGGED_REPO=$(create_test_repo 20 "5:v1.0,10:v2.0,15:v3.0")

TAGGED_OUTPUT=$(make_temp_dir)/eras.json
"$DETECT" "$TAGGED_REPO" > "$TAGGED_OUTPUT"

assert_json_valid "$TAGGED_OUTPUT" "tagged repo: output is valid JSON"
assert_json_array_min_length "$TAGGED_OUTPUT" 1 "tagged repo: at least 1 era"

# Check required fields on first era
assert_json_field "$TAGGED_OUTPUT" '.[0].name' "tagged repo: era has name"
assert_json_field "$TAGGED_OUTPUT" '.[0].start_ref' "tagged repo: era has start_ref"
assert_json_field "$TAGGED_OUTPUT" '.[0].end_ref' "tagged repo: era has end_ref"
assert_json_field "$TAGGED_OUTPUT" '.[0].start_date' "tagged repo: era has start_date"
assert_json_field "$TAGGED_OUTPUT" '.[0].end_date' "tagged repo: era has end_date"
assert_json_field "$TAGGED_OUTPUT" '.[0].commit_count' "tagged repo: era has commit_count"
assert_json_field "$TAGGED_OUTPUT" '.[0].contributor_count' "tagged repo: era has contributor_count"

# ── Untagged repo (60 commits) ──────────────────────────────────────────────

echo "  Setting up untagged repo (60 commits)..."
UNTAGGED_REPO=$(create_test_repo 60)

UNTAGGED_OUTPUT=$(make_temp_dir)/eras.json
"$DETECT" "$UNTAGGED_REPO" > "$UNTAGGED_OUTPUT"

assert_json_valid "$UNTAGGED_OUTPUT" "untagged repo: output is valid JSON"
assert_json_array_min_length "$UNTAGGED_OUTPUT" 1 "untagged repo: at least 1 era"

# ── Many tags → capped at MAX_ERAS (20) ─────────────────────────────────────

echo "  Setting up repo with 25 tags..."
# Build tag spec: tags at commits 4,8,12,...,100
TAG_SPEC=""
for ((i = 1; i <= 25; i++)); do
    cnum=$((i * 4))
    if [ -n "$TAG_SPEC" ]; then TAG_SPEC="$TAG_SPEC,"; fi
    TAG_SPEC="${TAG_SPEC}${cnum}:v${i}.0"
done
MANY_TAG_REPO=$(create_test_repo 104 "$TAG_SPEC")

MANY_TAG_OUTPUT=$(make_temp_dir)/eras.json
"$DETECT" "$MANY_TAG_REPO" > "$MANY_TAG_OUTPUT"

assert_json_valid "$MANY_TAG_OUTPUT" "many-tag repo: output is valid JSON"
ERA_COUNT=$(jq 'length' "$MANY_TAG_OUTPUT")
if [ "$ERA_COUNT" -le 20 ]; then
    pass "many-tag repo: capped at <= 20 eras (got $ERA_COUNT)"
else
    fail "many-tag repo: capped at <= 20 eras" "Got $ERA_COUNT eras"
fi

# ── No-arg invocation (uses cwd) ────────────────────────────────────────────

echo "  Testing no-arg invocation from inside repo..."
CWD_OUTPUT=$(make_temp_dir)/eras.json
(cd "$TAGGED_REPO" && "$DETECT") > "$CWD_OUTPUT"
assert_json_valid "$CWD_OUTPUT" "no-arg: works from inside repo (uses cwd)"

emit_results
