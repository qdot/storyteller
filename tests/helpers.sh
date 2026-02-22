#!/bin/bash
# helpers.sh — Shared assertion primitives and fixture builders for storyteller tests.
# Source this file from each test-*.sh script.

set -euo pipefail

# ── Result counters ──────────────────────────────────────────────────────────

PASS=0
FAIL=0
SKIP=0

# Track temp dirs for cleanup
_TEMP_DIRS=()

cleanup_temp_dirs() {
    for d in "${_TEMP_DIRS[@]+"${_TEMP_DIRS[@]}"}"; do
        rm -rf "$d" 2>/dev/null || true
    done
}
trap cleanup_temp_dirs EXIT

# Register a temp dir for cleanup
register_temp_dir() {
    _TEMP_DIRS+=("$1")
}

# Create and register a temp dir
make_temp_dir() {
    local d
    d=$(mktemp -d)
    register_temp_dir "$d"
    echo "$d"
}

# ── Resolve plugin root ─────────────────────────────────────────────────────

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Assertions ───────────────────────────────────────────────────────────────

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    if [ "${2:-}" != "" ]; then
        echo "        $2"
    fi
}

skip() {
    SKIP=$((SKIP + 1))
    echo "  SKIP: $1"
}

assert_file_exists() {
    local path="$1" label="${2:-file exists: $1}"
    if [ -f "$path" ]; then
        pass "$label"
    else
        fail "$label" "File not found: $path"
    fi
}

assert_file_executable() {
    local path="$1" label="${2:-file executable: $1}"
    if [ -x "$path" ]; then
        pass "$label"
    else
        fail "$label" "Not executable: $path"
    fi
}

assert_dir_exists() {
    local path="$1" label="${2:-dir exists: $1}"
    if [ -d "$path" ]; then
        pass "$label"
    else
        fail "$label" "Directory not found: $path"
    fi
}

assert_equals() {
    local expected="$1" actual="$2" label="${3:-equals}"
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label" "Expected: '$expected', Got: '$actual'"
    fi
}

assert_exit_code() {
    local expected="$1" label="$2"
    shift 2
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    if [ "$expected" = "nonzero" ]; then
        if [ "$actual" -ne 0 ]; then
            pass "$label"
        else
            fail "$label" "Expected nonzero exit code, got 0"
        fi
    else
        if [ "$actual" -eq "$expected" ]; then
            pass "$label"
        else
            fail "$label" "Expected exit code $expected, got $actual"
        fi
    fi
}

assert_json_valid() {
    local file="$1" label="${2:-valid JSON: $1}"
    if jq '.' "$file" > /dev/null 2>&1; then
        pass "$label"
    else
        fail "$label" "Invalid JSON in $file"
    fi
}

assert_json_field() {
    local file="$1" field="$2" label="${3:-JSON field $2 exists in $1}"
    local val
    val=$(jq -r "$field // empty" "$file" 2>/dev/null)
    if [ -n "$val" ]; then
        pass "$label"
    else
        fail "$label" "Field $field missing or empty in $file"
    fi
}

assert_json_array_min_length() {
    local file="$1" min="$2" label="${3:-JSON array has >= $2 elements}"
    local len
    len=$(jq 'length' "$file" 2>/dev/null || echo 0)
    if [ "$len" -ge "$min" ]; then
        pass "$label"
    else
        fail "$label" "Expected >= $min elements, got $len"
    fi
}

assert_contains() {
    local file="$1" pattern="$2" label="${3:-file contains: $2}"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        pass "$label"
    else
        fail "$label" "Pattern '$pattern' not found in $file"
    fi
}

assert_not_contains() {
    local file="$1" pattern="$2" label="${3:-file does not contain: $2}"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        pass "$label"
    else
        fail "$label" "Pattern '$pattern' unexpectedly found in $file"
    fi
}

# ── Fixture builders ─────────────────────────────────────────────────────────

# Create a test git repo with configurable commits, tags, and contributors.
# Usage: create_test_repo <commit_count> [tag_spec] [contributor_count]
#   tag_spec: comma-separated "commit_num:tag_name" pairs (e.g., "5:v1.0,10:v2.0")
#   contributor_count: number of distinct authors to rotate through (default: 1)
# Prints the repo path to stdout.
create_test_repo() {
    local commit_count="${1:-10}"
    local tag_spec="${2:-}"
    local contributor_count="${3:-1}"

    local repo_dir
    repo_dir=$(make_temp_dir)

    git -C "$repo_dir" init -q
    git -C "$repo_dir" config user.email "test@storyteller.dev"
    git -C "$repo_dir" config user.name "Test Author"

    # Parse tag spec into associative-like arrays
    local -a tag_commits=()
    local -a tag_names=()
    if [ -n "$tag_spec" ]; then
        IFS=',' read -ra pairs <<< "$tag_spec"
        for pair in "${pairs[@]}"; do
            IFS=':' read -r cnum tname <<< "$pair"
            tag_commits+=("$cnum")
            tag_names+=("$tname")
        done
    fi

    local authors=()
    for ((a = 1; a <= contributor_count; a++)); do
        authors+=("Author$a")
    done

    for ((i = 1; i <= commit_count; i++)); do
        local author_idx=$(( (i - 1) % contributor_count ))
        local author="${authors[$author_idx]}"
        local date_ts=$((1700000000 + i * 86400))
        local date_str
        date_str=$(date -r "$date_ts" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -d "@$date_ts" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)

        echo "commit $i" > "$repo_dir/file.txt"
        git -C "$repo_dir" add file.txt
        GIT_AUTHOR_NAME="$author" \
        GIT_AUTHOR_EMAIL="${author}@test.dev" \
        GIT_AUTHOR_DATE="$date_str" \
        GIT_COMMITTER_NAME="$author" \
        GIT_COMMITTER_EMAIL="${author}@test.dev" \
        GIT_COMMITTER_DATE="$date_str" \
        git -C "$repo_dir" commit -q -m "Commit $i by $author"

        # Check if this commit should be tagged
        for ((t = 0; t < ${#tag_commits[@]}; t++)); do
            if [ "${tag_commits[$t]}" -eq "$i" ]; then
                git -C "$repo_dir" tag "${tag_names[$t]}"
            fi
        done
    done

    echo "$repo_dir"
}

# ── Result emission ──────────────────────────────────────────────────────────

emit_results() {
    echo "RESULTS: pass=$PASS fail=$FAIL skip=$SKIP"
}
