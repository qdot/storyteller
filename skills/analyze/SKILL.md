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

Store these in variables for use throughout the phases. Resolve all paths to absolute paths.

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

## Phase 2: Beads Initialization

After the user confirms eras, initialize the Beads workspace and create tracking issues.

**Step 1: Select workspace location**

Determine where to initialize Beads:
- If the target repo's `.beads/` directory does NOT exist and the repo is writable, use the target repo directory.
- Otherwise, use the output directory (create it first if needed).

Test writability:
```bash
touch <repo-path>/.beads-test && rm <repo-path>/.beads-test
```

**Step 2: Initialize Beads workspace**

```bash
cd <workspace-location>
br init --prefix ST
```

**Step 3: Create one issue per confirmed era**

For each era, create a Beads issue:
```bash
br create "Research era: <era-name>" -p 1 -d "Era: <era-name>\nStart: <start_ref> (<start_date>)\nEnd: <end_ref> (<end_date>)\nCommits: <commit_count>\nContributors: <contributor_count>"
```

Capture each issue ID from the output (e.g., ST-1, ST-2, ...).

**Step 4: Verify issues created**

```bash
br list --format json
```

## Phase 3: Parallel Era Research

Fan out era-researcher agents in parallel — one per era. Collect all results.

**CRITICAL: Make ALL Task tool calls in a SINGLE response to enable parallel execution.**

**Step 1: Dispatch era-researcher agents**

For each confirmed era, make one Task tool call with `subagent_type: "era-researcher"`:

```
Task tool call for each era:
  subagent_type: "era-researcher"
  description: "Research era: <era-name>"
  prompt: |
    Research the following era of the git repository:

    REPO_PATH: <absolute-repo-path>
    ERA_NAME: <era-name>
    START_REF: <start_ref>
    END_REF: <end_ref>
    START_DATE: <start_date>
    END_DATE: <end_date>
    BEADS_ISSUE_ID: <issue-id>
    BEADS_DB: <absolute-path-to-beads-db>
    DOCS_REPO_PATH: <docs-repo-path or omit if not provided>
    CHANGELOG_PATH: <changelog-path or omit if not provided>

    Follow the instructions in your agent definition to perform layered analysis
    and return a structured JSON report.
```

Make ALL these Task calls in one message. Claude Code will execute them in parallel.

**Step 2: Collect results**

After all agents complete, collect the JSON reports from each. Parse the JSON from each agent's response.

**Step 3: Handle partial failures**

Some agents may fail (timeout, context overflow). For each agent:
- If succeeded: add its JSON report to the results collection
- If failed: record the failure with the era name and error

If ANY agents succeeded, continue to Phase 4 with available data.

Report to the user:
- "Successfully researched [N] of [M] eras."
- For each failure: "Era '<name>' failed: <error>. Consider splitting this era (it had <commit_count> commits)."

If ALL agents failed, stop and report the error to the user.

## Status

Phases 4-6 are not yet implemented:
- Phase 4: Narrative Synthesis (Phase 6)
- Phase 5: Timeline Generation (Phase 7)
- Phase 6: End-to-End Integration (Phase 8)
