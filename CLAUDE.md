# Storyteller

Last verified: 2026-02-21

## Purpose

Claude Code plugin that turns a git repository's commit history into an interactive TimelineJS3 timeline. Analyzes eras of development via parallel subagents and synthesizes narrative-driven visual output.

## Tech Stack

- Runtime: Claude Code plugin (`.claude-plugin/plugin.json`)
- Timeline rendering: TimelineJS3 (`@knight-lab/timelinejs ^3.9.8`, vendored via npm)
- Scripts: Bash (requires `jq`)
- Output: Self-contained HTML directory

## Project Structure

- `.claude-plugin/` - Plugin manifest
- `skills/analyze/` - Main orchestrator skill (`/storyteller:analyze`)
- `agents/` - Subagent definitions (era-researcher, narrative-synthesizer)
- `scripts/` - Bash scripts for era detection and HTML assembly
- `templates/` - HTML template for TimelineJS3 viewer
- `docs/` - Design and implementation plans

## Key Workflow

The analyze skill runs 6 phases sequentially:
1. Era detection (`scripts/detect-eras.sh`) with user confirmation
2. README snapshot extraction at era boundaries
3. Beads issue tracking initialization (with resume support)
4. Parallel era research via `era-researcher` subagents (fan-out)
5. Narrative synthesis via `narrative-synthesizer` subagent
6. HTML generation (`scripts/generate-timeline.sh`)

## Conventions

- Subagents receive structured prompts with uppercase variable names (REPO_PATH, ERA_NAME, etc.)
- All paths passed between components must be absolute
- JSON is the interchange format between all components
- Era detection outputs JSON array to stdout; errors go to stderr
- The plugin uses `${CLAUDE_PLUGIN_ROOT}` to reference its own files

## Boundaries

- Never modify the target repository being analyzed
- `node_modules/` and `storyteller-output/` are gitignored
- Beads workspace (`.beads/`) is created in the target repo or output dir, never in the plugin
