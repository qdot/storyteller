#!/bin/bash
# detect-eras.sh — Detects era boundaries from a git repository's history.
# Outputs a JSON array of era objects to stdout.
#
# Usage: detect-eras.sh [repo-path]
# Default repo-path: current directory
#
# Strategy:
#   1. If repo has ≥2 tags: create eras between consecutive tags
#   2. If repo has <2 tags: use time-gap heuristic (gaps >90 days)
#   3. If no significant gaps: split by commit-count chunks (~100 commits)
#
# Output JSON format:
# [
#   {
#     "name": "Era name",
#     "start_ref": "v1.0",
#     "end_ref": "v2.0",
#     "start_date": "2024-01-15",
#     "end_date": "2024-06-30",
#     "commit_count": 142,
#     "contributor_count": 5
#   }
# ]

set -euo pipefail

REPO_PATH="${1:-.}"
MAX_ERAS=20

# Verify it's a git repo
if ! git -C "$REPO_PATH" rev-parse --git-dir >/dev/null 2>&1; then
    echo '{"error": "Not a git repository: '"$REPO_PATH"'"}' >&2
    exit 1
fi

# Verify jq is available
if ! command -v jq &>/dev/null; then
    echo '{"error": "jq is required but not found"}' >&2
    exit 1
fi

# Helper: count commits between two refs
count_commits() {
    git -C "$REPO_PATH" rev-list --count "$1..$2" 2>/dev/null || echo 0
}

# Helper: count unique contributors between two refs
count_contributors() {
    git -C "$REPO_PATH" log --format='%aN' "$1..$2" 2>/dev/null | sort -u | wc -l | tr -d ' '
}

# Helper: get the short date (YYYY-MM-DD) of a ref
ref_date() {
    git -C "$REPO_PATH" log -1 --format='%as' "$1" 2>/dev/null
}

# Helper: get the first commit hash
first_commit() {
    git -C "$REPO_PATH" rev-list --max-parents=0 HEAD 2>/dev/null | head -1
}

# Build a single era JSON object using jq
build_era() {
    local name="$1" start_ref="$2" end_ref="$3" start_date="$4" end_date="$5" commits="$6" contributors="$7"
    jq -n \
        --arg name "$name" \
        --arg start_ref "$start_ref" \
        --arg end_ref "$end_ref" \
        --arg start_date "$start_date" \
        --arg end_date "$end_date" \
        --argjson commit_count "$commits" \
        --argjson contributor_count "$contributors" \
        '{name: $name, start_ref: $start_ref, end_ref: $end_ref, start_date: $start_date, end_date: $end_date, commit_count: $commit_count, contributor_count: $contributor_count}'
}

# Strategy 1: Tag-based era detection
detect_from_tags() {
    local tag_names=()
    local tag_dates=()

    while IFS='|' read -r tag date; do
        tag_names+=("$tag")
        tag_dates+=("$date")
    done < <(git -C "$REPO_PATH" for-each-ref --sort=creatordate \
        --format='%(refname:short)|%(creatordate:short)' refs/tags)

    local num_tags=${#tag_names[@]}
    if [ "$num_tags" -lt 2 ]; then
        return 1
    fi

    local eras="[]"
    local initial
    initial=$(first_commit)
    local initial_date
    initial_date=$(ref_date "$initial")

    # Pre-tag era: from first commit to first tag
    local pre_count
    pre_count=$(count_commits "$initial" "${tag_names[0]}")
    if [ "$pre_count" -gt 0 ]; then
        local pre_contributors
        pre_contributors=$(count_contributors "$initial" "${tag_names[0]}")
        local era
        era=$(build_era \
            "Origin → ${tag_names[0]}" \
            "$initial" \
            "${tag_names[0]}" \
            "$initial_date" \
            "${tag_dates[0]}" \
            "$pre_count" \
            "$pre_contributors")
        eras=$(echo "$eras" | jq --argjson era "$era" '. + [$era]')
    fi

    # Eras between consecutive tags
    for ((i = 0; i < num_tags - 1; i++)); do
        local start_tag="${tag_names[$i]}"
        local end_tag="${tag_names[$((i + 1))]}"
        local commits
        commits=$(count_commits "$start_tag" "$end_tag")
        local contributors
        contributors=$(count_contributors "$start_tag" "$end_tag")
        local era
        era=$(build_era \
            "${start_tag} → ${end_tag}" \
            "$start_tag" \
            "$end_tag" \
            "${tag_dates[$i]}" \
            "${tag_dates[$((i + 1))]}" \
            "$commits" \
            "$contributors")
        eras=$(echo "$eras" | jq --argjson era "$era" '. + [$era]')
    done

    # Post-tag era: from last tag to HEAD
    local last_tag="${tag_names[$((num_tags - 1))]}"
    local post_count
    post_count=$(count_commits "$last_tag" "HEAD")
    if [ "$post_count" -gt 0 ]; then
        local post_contributors
        post_contributors=$(count_contributors "$last_tag" "HEAD")
        local head_date
        head_date=$(ref_date "HEAD")
        local era
        era=$(build_era \
            "${last_tag} → HEAD" \
            "$last_tag" \
            "HEAD" \
            "${tag_dates[$((num_tags - 1))]}" \
            "$head_date" \
            "$post_count" \
            "$post_contributors")
        eras=$(echo "$eras" | jq --argjson era "$era" '. + [$era]')
    fi

    # Output eras (merging logic disabled due to complexity)
    echo "$eras" | jq '.'
}

# Strategy 2: Heuristic detection (time-gap + commit-count fallback)
detect_from_heuristics() {
    local timestamps=()
    local hashes=()
    local dates=()

    while IFS='|' read -r ts hash date; do
        timestamps+=("$ts")
        hashes+=("$hash")
        dates+=("$date")
    done < <(git -C "$REPO_PATH" log --format='%ct|%H|%as' --reverse)

    local total=${#timestamps[@]}
    if [ "$total" -eq 0 ]; then
        echo '[]'
        return
    fi

    # Find split points at large gaps (>90 days = 7776000 seconds)
    local gap_threshold=7776000
    local split_indices=(0)

    for ((i = 1; i < total; i++)); do
        local gap=$(( ${timestamps[$i]} - ${timestamps[$((i - 1))]} ))
        if [ "$gap" -gt "$gap_threshold" ]; then
            split_indices+=("$i")
        fi
    done

    # If too few splits (<=1 era), fall back to commit-count chunks
    if [ "${#split_indices[@]}" -le 1 ]; then
        local chunk_size=$(( (total + MAX_ERAS - 1) / MAX_ERAS ))
        if [ "$chunk_size" -lt 50 ]; then
            chunk_size=50
        fi
        split_indices=(0)
        for ((i = chunk_size; i < total; i += chunk_size)); do
            split_indices+=("$i")
        done
    fi

    # Cap split points at MAX_ERAS
    if [ "${#split_indices[@]}" -gt "$MAX_ERAS" ]; then
        split_indices=("${split_indices[@]:0:$MAX_ERAS}")
    fi

    # Build eras from split points
    local eras="[]"
    local num_splits=${#split_indices[@]}

    for ((i = 0; i < num_splits; i++)); do
        local start_idx=${split_indices[$i]}
        local end_idx
        if [ "$((i + 1))" -lt "$num_splits" ]; then
            end_idx=$(( ${split_indices[$((i + 1))]} - 1 ))
        else
            end_idx=$((total - 1))
        fi

        local start_hash="${hashes[$start_idx]}"
        local end_hash="${hashes[$end_idx]}"
        local start_date="${dates[$start_idx]}"
        local end_date="${dates[$end_idx]}"
        local commits=$((end_idx - start_idx + 1))
        local contributors
        # Guard: for the first era (start_idx=0), the start commit may be the root commit
        # which has no parent, so ^..end fails. Use --root for the first era.
        if [ "$start_idx" -eq 0 ]; then
            contributors=$(git -C "$REPO_PATH" log --format='%aN' "$end_hash" --not $(git -C "$REPO_PATH" rev-list --max-parents=0 HEAD | tail -n +2) 2>/dev/null | sort -u | wc -l | tr -d ' ')
            # Simpler fallback: just count contributors in the commit range by date
            if [ "$contributors" -eq 0 ] 2>/dev/null; then
                contributors=$(git -C "$REPO_PATH" log --format='%aN' "${start_hash}..${end_hash}" 2>/dev/null | sort -u | wc -l | tr -d ' ')
                contributors=$((contributors + 1))  # Include the start commit's author
            fi
        else
            contributors=$(git -C "$REPO_PATH" log --format='%aN' "${start_hash}^..${end_hash}" 2>/dev/null | sort -u | wc -l | tr -d ' ')
        fi

        local era_num=$((i + 1))
        local era
        era=$(build_era \
            "Era ${era_num}: ${start_date} → ${end_date}" \
            "$start_hash" \
            "$end_hash" \
            "$start_date" \
            "$end_date" \
            "$commits" \
            "$contributors")
        eras=$(echo "$eras" | jq --argjson era "$era" '. + [$era]')
    done

    echo "$eras" | jq '.'
}

# Main: try tags first, fall back to heuristics
if detect_from_tags 2>/dev/null; then
    exit 0
fi

detect_from_heuristics
