# Agents

Last verified: 2026-02-21

## Purpose

Subagent definitions dispatched by the analyze skill via the Task tool. Each agent runs in its own context with restricted tool access.

## Contracts

### era-researcher

- **Exposes**: JSON report with era metadata, key_changes array, and narrative_summary
- **Guarantees**: Self-limits to ~50 impactful commits (30 for 500+ commit eras). Always closes Beads issue on completion, even if partial. Never modifies the repository.
- **Expects**: Prompt with REPO_PATH, ERA_NAME, START_REF, END_REF, START_DATE, END_DATE, BEADS_ISSUE_ID, BEADS_DB. Optional: DOCS_REPO_PATH, CHANGELOG_PATH, README_SNAPSHOT.
- **Tools**: Read, Grep, Glob, Bash
- **Model**: sonnet

### narrative-synthesizer

- **Exposes**: `timeline-data.json` file in TimelineJS3 format (title slide + event slides)
- **Guarantees**: Validates output with `jq`. Dates are TimelineJS3 date objects (`{year, month, day}`). HTML formatting in text fields uses `<p>`, `<strong>`, `<em>`, `<ul>`, `<li>`.
- **Expects**: Prompt with PROJECT_NAME, REPO_PATH, OUTPUT_PATH, ERA_REPORTS (JSON array).
- **Tools**: Read, Bash
- **Model**: sonnet

## Key Decisions

- Sonnet model for both agents: cost efficiency for parallel fan-out pattern
- Layered analysis in era-researcher (L1 metadata, L2 selective deep-dive): prevents context overflow on large eras
