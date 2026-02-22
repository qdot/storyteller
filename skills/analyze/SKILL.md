---
name: analyze
description: "Analyze a git repository's history and generate an interactive TimelineJS3 timeline showing the project's growth story."
---

# Storyteller: Analyze

Analyze a git repository's commit history and produce an interactive timeline.

## Usage

```
/storyteller:analyze [repo-path] [--docs-repo <path>] [--changelog <path>] [--output <path>]
```

## Step 0: Parse Arguments

Parse arguments from `$ARGUMENTS`:

```
REPO_PATH = first positional argument, or current working directory if not provided
DOCS_REPO = value after --docs-repo flag, or empty
CHANGELOG = value after --changelog flag, or empty
OUTPUT_DIR = value after --output flag, or "./storyteller-output/"
```

Resolve all paths to absolute paths using `realpath` or `cd && pwd`.

Verify the target is a git repository:
```bash
git -C <REPO_PATH> rev-parse --git-dir
```

**Note:** This first bash command triggers the Bash tool permission prompt. The user must grant permission here — it is required for era detection scripts, Beads initialization, and era-researcher subagents' git commands in Phase 3.

If not a git repo, report the error and stop.

Determine the project name from the repository directory name:
```bash
basename <REPO_PATH>
```

## Phase 1: Era Detection

**Step 1: Run era detection**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-eras.sh <REPO_PATH>
```

Parse the JSON output into an era list.

**Step 2: Present eras to user**

Display detected eras as a table:

| # | Era | Date Range | Commits | Contributors |
|---|-----|-----------|---------|-------------|
| 1 | Origin → v1.0 | 2023-01-15 → 2023-06-30 | 142 | 5 |
| 2 | v1.0 → v2.0 | 2023-06-30 → 2024-01-15 | 230 | 8 |

**Step 3: Ask for confirmation**

Use AskUserQuestion:
```
Question: "Storyteller detected [N] eras. Proceed with analysis or adjust?"
Options:
  - "Proceed with these eras"
  - "I'd like to adjust era boundaries"
```

If adjustment requested, ask which eras to merge, split, or remove, then re-present.

## Phase 1.5: README Snapshot Extraction

Before researching eras, extract README snapshots at era boundaries to provide context to era-researcher agents.

**Step 1: Extract README at each era boundary ref**

For each era's `end_ref`, attempt to extract the README:
```bash
git -C <REPO_PATH> show <end_ref>:README.md 2>/dev/null || git -C <REPO_PATH> show <end_ref>:README 2>/dev/null || git -C <REPO_PATH> show <end_ref>:README.rst 2>/dev/null || echo ""
```

Store each snapshot as `README_SNAPSHOT_<era-index>`. These will be passed to era-researcher agents in Phase 3.

## Phase 2: Beads Initialization

**Step 0: Check for existing Beads workspace (resume support)**

Check if a previous run already created a Beads workspace:
```bash
# Check target repo first, then output dir
if [ -d "<REPO_PATH>/.beads" ]; then
    BEADS_DIR="<REPO_PATH>"
elif [ -d "<OUTPUT_DIR>/.beads" ]; then
    BEADS_DIR="<OUTPUT_DIR>"
fi
```

If an existing workspace is found with ST-prefixed issues:
```bash
br --db <BEADS_DIR>/.beads/beads.db list --format json
```

Parse the issue list. For any issues with status `"closed"`, skip those eras in Phase 3 (they were already researched). For issues with status `"in_progress"` or `"open"`, re-research those eras.

Report to the user: "Found existing Storyteller workspace. Resuming: [N] eras already complete, [M] remaining."

If no existing workspace is found, proceed with fresh initialization.

**Step 1: Select workspace location**

```bash
# Test if target repo is writable and doesn't already have .beads/
if [ ! -d "<REPO_PATH>/.beads" ] && touch "<REPO_PATH>/.beads-test" 2>/dev/null; then
    rm "<REPO_PATH>/.beads-test"
    BEADS_DIR="<REPO_PATH>"
else
    mkdir -p "<OUTPUT_DIR>"
    BEADS_DIR="<OUTPUT_DIR>"
fi
```

**Step 2: Initialize and create issues**

```bash
cd <BEADS_DIR>
br init --prefix ST
```

For each confirmed era:
```bash
br create "Research era: <era-name>" -p 1 -d "<era details>"
```

Capture the issue IDs (ST-1, ST-2, ...) from the output.

**Step 3: Verify**

```bash
br list --format json
```

## Phase 3: Parallel Era Research

**CRITICAL: Make ALL Task tool calls in a SINGLE response.**

For each era, dispatch one `era-researcher` agent via the Task tool:

```
subagent_type: "era-researcher"
description: "Research era: <era-name>"
prompt: |
  REPO_PATH: <absolute-repo-path>
  ERA_NAME: <era-name>
  START_REF: <start_ref>
  END_REF: <end_ref>
  START_DATE: <start_date>
  END_DATE: <end_date>
  BEADS_ISSUE_ID: <issue-id>
  BEADS_DB: <absolute-path-to-beads-db>
  DOCS_REPO_PATH: <if provided>
  CHANGELOG_PATH: <if provided>
  README_SNAPSHOT: <README content at end_ref, if extracted>
```

**Note on resume:** If resuming from a previous run, only dispatch agents for eras whose Beads issues are NOT closed. Skip already-completed eras.

After all agents complete:
- Collect successful JSON reports
- Record any failures

Report progress: "Successfully researched [N] of [M] eras."

For failures: "Era '<name>' failed: <error>. Consider splitting this era."

If ALL agents failed, stop and report.

## Phase 4: Narrative Synthesis

Dispatch the `narrative-synthesizer` agent via the Task tool:

```
subagent_type: "narrative-synthesizer"
description: "Synthesize timeline narrative"
prompt: |
  PROJECT_NAME: <project-name>
  REPO_PATH: <absolute-repo-path>
  OUTPUT_PATH: <absolute-output-dir>
  ERA_REPORTS: <JSON array of all successful era reports>
```

The synthesizer writes `timeline-data.json` to the output directory.

## Phase 5: Timeline Generation

Run the generation script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/generate-timeline.sh <OUTPUT_DIR>/timeline-data.json <OUTPUT_DIR> ${CLAUDE_PLUGIN_ROOT}
```

## Phase 6: Final Report

Present the results to the user:

```
Storyteller timeline complete!

Timeline: <OUTPUT_DIR>/index.html
Eras analyzed: [N] of [M]
Contributors found: [total unique]
Time span: [first date] → [last date]

Open the timeline:
  open <OUTPUT_DIR>/index.html
```

If there were partial failures, include:
```
Note: [K] era(s) could not be analyzed:
  - <era-name>: <error reason>
```

## Edge Cases

**Repository with no tags:**
The detect-eras.sh script automatically falls back to time-gap heuristics, then commit-count chunking. No special handling needed.

**Very large eras (500+ commits):**
The era-researcher agent self-limits to 30 impactful commits for Layer 2 deep-dive. If an agent fails due to context overflow, suggest to the user: "Consider splitting era '<name>' into sub-eras for more detailed analysis."

**Read-only repository:**
Beads workspace is created in the output directory instead of the target repo. This is handled automatically in Phase 2.

**Docs repo with different branch structure:**
When correlating docs-repo changes to eras, use date-range filtering (`git log --after --before`) rather than tag matching:
```bash
git -C <DOCS_REPO_PATH> log --format='%as %s' --after=<START_DATE> --before=<END_DATE>
```

**Repository with only one commit:**
detect-eras.sh produces a single era. The timeline will have one event slide.

**Empty output from detect-eras.sh:**
If no eras are detected (empty JSON array), report to the user: "No eras could be detected. The repository may have too few commits." and stop.
