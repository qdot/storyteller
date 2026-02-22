#!/bin/bash
# run-tests.sh — Discovers and runs all test-*.sh suites, aggregates results.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
SUITE_COUNT=0
FAILED_SUITES=()

echo "╔══════════════════════════════════════════╗"
echo "║       Storyteller Test Runner            ║"
echo "╚══════════════════════════════════════════╝"
echo ""

for test_file in "$SCRIPT_DIR"/test-*.sh; do
    [ -f "$test_file" ] || continue
    suite_name=$(basename "$test_file" .sh)
    SUITE_COUNT=$((SUITE_COUNT + 1))

    echo "── $suite_name ──"
    output=$(bash "$test_file" 2>&1) || true
    echo "$output"

    # Parse the RESULTS line
    results_line=$(echo "$output" | grep '^RESULTS:' | tail -1)
    if [ -z "$results_line" ]; then
        echo "  ERROR: No RESULTS line emitted"
        FAILED_SUITES+=("$suite_name (no results)")
        continue
    fi

    suite_pass=$(echo "$results_line" | sed 's/.*pass=\([0-9]*\).*/\1/')
    suite_fail=$(echo "$results_line" | sed 's/.*fail=\([0-9]*\).*/\1/')
    suite_skip=$(echo "$results_line" | sed 's/.*skip=\([0-9]*\).*/\1/')

    TOTAL_PASS=$((TOTAL_PASS + suite_pass))
    TOTAL_FAIL=$((TOTAL_FAIL + suite_fail))
    TOTAL_SKIP=$((TOTAL_SKIP + suite_skip))

    if [ "$suite_fail" -gt 0 ]; then
        FAILED_SUITES+=("$suite_name ($suite_fail failures)")
    fi

    echo ""
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo "══════════════════════════════════════════"
echo "Suites:  $SUITE_COUNT"
echo "Pass:    $TOTAL_PASS"
echo "Fail:    $TOTAL_FAIL"
echo "Skip:    $TOTAL_SKIP"
echo "Total:   $((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))"
echo "══════════════════════════════════════════"

if [ "$TOTAL_FAIL" -gt 0 ]; then
    echo ""
    echo "FAILED SUITES:"
    for s in "${FAILED_SUITES[@]}"; do
        echo "  - $s"
    done
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
