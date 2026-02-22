# Scripts

Last verified: 2026-02-21

## Purpose

Bash utilities called by the orchestrator skill. Handle era boundary detection and final HTML assembly.

## Contracts

### detect-eras.sh

- **Usage**: `detect-eras.sh [repo-path]` (default: current directory)
- **Guarantees**: Outputs JSON array of era objects to stdout. Errors to stderr with exit 1. Caps at 20 eras (merges smallest adjacent pairs when exceeded).
- **Expects**: Valid git repository path. `jq` available on PATH.
- **Strategy cascade**: (1) Tag-based if >=2 tags, (2) time-gap heuristic (>90 day gaps), (3) commit-count chunks (~100 per era)
- **Era object shape**: `{name, start_ref, end_ref, start_date, end_date, commit_count, contributor_count}`

### generate-timeline.sh

- **Usage**: `generate-timeline.sh <timeline-data.json> <output-dir> <plugin-root>`
- **Guarantees**: Creates self-contained output directory with index.html, vendored TimelineJS3 assets, and timeline data. Validates JSON input with jq before copying.
- **Expects**: Valid timeline-data.json, plugin-root with `node_modules/@knight-lab/timelinejs/dist/` and `templates/timeline.html`.
- **Output structure**: `output-dir/{index.html, timeline-data.json, assets/{js/, css/}}`

## Invariants

- detect-eras.sh never modifies the repository
- generate-timeline.sh output is fully self-contained (no CDN dependencies)
- Both scripts use `set -euo pipefail`
