# Agents

Last verified: 2026-02-21

## Purpose

Subagent definitions dispatched by the analyze skill via the Task tool. Each agent runs in its own context with restricted tool access.

## Contracts

### era-researcher

- **Exposes**: JSON report persisted to `ERA_REPORTS_DIR/<slug>.json` with era metadata, key_changes array, and narrative_summary. Returns confirmation message with file path (not raw JSON).
- **Guarantees**: Self-limits to ~50 impactful commits (30 for 500+ commit eras). Persists report to disk and validates with jq before closing. Adds Beads comment with file path. Always closes Beads issue on completion, even if partial. Never modifies the repository.
- **Expects**: Prompt with REPO_PATH, ERA_NAME, START_REF, END_REF, START_DATE, END_DATE, BEADS_ISSUE_ID, BEADS_DB, ERA_REPORTS_DIR. Optional: DOCS_REPO_PATH, CHANGELOG_PATH, README_SNAPSHOT.
- **Tools**: Read, Grep, Glob, Bash
- **Model**: sonnet

### narrative-synthesizer

- **Exposes**: `timeline-data.json` file in TimelineJS3 format (title slide + event slides)
- **Guarantees**: Discovers and loads report files from disk via Glob. Validates JSON structure before writing. Dates are TimelineJS3 date objects (`{year, month, day}`). HTML formatting in text fields uses `<p>`, `<strong>`, `<em>`, `<ul>`, `<li>`.
- **Expects**: Prompt with PROJECT_NAME, REPO_PATH, OUTPUT_PATH, ERA_REPORTS_DIR (directory path).
- **Tools**: Read, Write, Glob
- **Model**: sonnet

## Key Decisions

- Sonnet model for both agents: cost efficiency for parallel fan-out pattern
- Layered analysis in era-researcher (L1 metadata, L2 selective deep-dive): prevents context overflow on large eras
