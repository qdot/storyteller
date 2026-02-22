---
name: analyze
description: "Analyze a git repository's history and generate an interactive TimelineJS3 timeline showing the project's growth story."
---

# Storyteller: Analyze

Analyze a git repository's commit history and produce an interactive timeline.

## Usage

The user invokes this skill as:
```
/storyteller:analyze [repo-path] [--docs-repo <path>] [--changelog <path>] [--output <path>]
```

## Arguments

Parse the arguments from `$ARGUMENTS`:
- First positional argument: repository path (default: current working directory)
- `--docs-repo <path>`: optional separate documentation repository
- `--changelog <path>`: optional changelog file (CHANGELOG.md, HISTORY.md, etc.)
- `--output <path>`: output directory (default: `./storyteller-output/`)

## Phase 1: Era Detection

Run the era detection script to identify time periods in the repository's history.

**Step 1: Run era detection**

Use the Bash tool to run the detection script:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-eras.sh <repo-path>
```

The script outputs a JSON array of era objects with fields: name, start_ref, end_ref, start_date, end_date, commit_count, contributor_count.

**Step 2: Present eras to user**

Display the detected eras in a readable table format showing:
- Era name (e.g., "v1.0 → v2.0")
- Date range
- Commit count
- Contributor count

**Step 3: Ask user for overrides**

Use AskUserQuestion to let the user confirm or adjust:
```
Question: "These eras were detected from your repository. Would you like to proceed or adjust?"
Options:
  - "Proceed with these eras"
  - "I'd like to adjust era boundaries"
```

If the user wants adjustments, ask follow-up questions about which eras to merge, split, or remove.

## Status

Phases 3-8 are not yet implemented:
- Phase 3: Beads Integration
- Phase 4-5: Era Research
- Phase 6: Narrative Synthesis
- Phase 7: Timeline Generation
- Phase 8: End-to-End Integration & Polish
