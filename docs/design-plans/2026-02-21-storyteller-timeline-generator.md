# Storyteller: Git History Timeline Generator

## Summary

Storyteller is a Claude Code plugin that turns a git repository's commit history into a visual, interactive timeline. When a user runs `/storyteller:analyze`, a coordinator skill orchestrates four sequential phases: era detection, parallel era research, narrative synthesis, and HTML generation. Era boundaries are identified automatically from git tags, with a heuristic fallback for repositories that have none, and the user can review and adjust them before analysis begins. Each confirmed era is then handed off to an independent subagent that digs into the git history for that period -- first collecting aggregate statistics, then selectively reading source code for the most significant commits -- and returns a structured JSON report. A final synthesis agent weaves those reports into a coherent narrative, and a shell script assembles the result into a self-contained, offline-capable HTML directory powered by TimelineJS3.

The design prioritizes parallelism and resilience. Era research agents run concurrently and report their progress through Beads, a lightweight CLI issue tracker that also provides an audit trail and supports resuming interrupted runs. Partial failures (for example, an era with an unusually large number of commits) are surfaced to the user rather than silently aborting the entire run. Optional supplementary inputs -- a separate docs repository, a changelog file, or README snapshots extracted at each era boundary -- allow the generated narratives to draw on more context than the commit log alone can provide.

## Definition of Done

Storyteller is a Claude Code plugin that, when invoked, analyzes a target git repository's history and produces an interactive TimelineJS3 webpage showing the project's growth story. A coordinator agent auto-detects "eras" (via tags, with heuristic fallback) and fans out subagents to research each era in parallel -- collecting metadata (commit stats, contributors, file changes) as a baseline, then selectively deep-diving into source code for the most significant changes. Agents coordinate via Beads. The output is a self-contained HTML directory the user can open in a browser. Users can optionally override era boundaries before analysis begins.

**Out of scope:** Modifying the target repository, real-time/live updating, hosted deployment infrastructure.

## Glossary

- **Claude Code**: Anthropic's official CLI for Claude, which supports plugins and skills that extend its behavior with custom commands and agents.
- **Plugin**: A Claude Code extension loaded via `--plugin-dir`, defined by a `plugin.json` manifest. Provides skills and agents scoped to a project.
- **Skill**: A Claude Code concept; a named, invocable command defined by a `SKILL.md` file. The `/storyteller:analyze` entry point is a skill.
- **Agent (subagent)**: A Claude Code concept; a reusable AI worker defined by a markdown file with YAML frontmatter. Skills can dispatch agents as parallel or sequential subtasks using the Task tool.
- **Era**: A distinct period in a repository's history used as the unit of analysis. Detected from git tags or inferred heuristically from time gaps and commit counts.
- **Era detection**: The process of dividing a repository's full git history into labeled time periods (eras) for individual research. Implemented in `detect-eras.sh`.
- **Fan-out**: An orchestration pattern where a coordinator launches multiple parallel workers (here, one era-researcher agent per era) and collects their results before proceeding.
- **Beads / `br` CLI**: A lightweight CLI issue tracker (`beads_rust`) used as a coordination hub between the orchestrator skill and era-researcher agents. Tracks work item state (`pending` -> `in_progress` -> `closed`) and provides an audit trail.
- **TimelineJS3**: An open-source JavaScript library that renders an interactive, scrollable timeline from a JSON data file. Used as the output format for the generated webpage.
- **Vendored**: Assets (here, TimelineJS3's CSS and JS) that are bundled directly into the project output rather than loaded from an external CDN, enabling offline use.
- **Narrative synthesis**: Phase 3 of the pipeline; a dedicated agent reads all era JSON reports and produces the final TimelineJS3 JSON, identifying cross-era themes and writing headlines and summaries.
- **Supplementary context**: Optional user-provided inputs (`--docs-repo`, `--changelog`) that era agents use alongside the git log to enrich their narratives.
- **README snapshot**: A copy of a repository's README at a specific git tag, extracted via `git show <tag>:README.md`, used to track how a project described itself at each era boundary.
- **Layered analysis**: The era-researcher's two-pass strategy: Layer 1 collects aggregate metadata from the full era; Layer 2 selectively reads source code for only the most impactful commits.

## Architecture

Storyteller is a Claude Code plugin with a skill-driven sequential fan-out architecture. A main orchestrator skill drives four phases: era detection, parallel research, narrative synthesis, and timeline generation. Agents coordinate through Beads (`br` CLI) as the central work-tracking hub.

### Plugin Structure

```
storyteller/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── agents/
│   ├── era-researcher.md        # Subagent: analyzes one era
│   └── narrative-synthesizer.md # Subagent: combines era reports into timeline
├── skills/
│   └── analyze/
│       └── SKILL.md             # Main orchestrator skill
├── scripts/
│   ├── detect-eras.sh           # Git analysis for era boundaries
│   └── generate-timeline.sh     # Assembles TimelineJS3 HTML output
└── templates/
    └── timeline.html            # TimelineJS3 HTML template with vendored assets
```

### Invocation

```
/storyteller:analyze [optional-repo-path] [--docs-repo <path>] [--changelog <path>] [--output <path>]
```

- Default target: current working directory
- Default output: `./storyteller-output/`

### Data Flow

```
User invokes /storyteller:analyze
        │
        ▼
[Phase 1: Era Detection]
  scripts/detect-eras.sh analyzes git tags, log, commit patterns
  Skill presents eras to user for optional override
  Skill initializes Beads, creates one issue per confirmed era
        │
        ▼
[Phase 2: Parallel Era Research]
  Skill fans out N parallel Task calls → era-researcher agents
  Each agent receives: era boundaries, Beads issue ID, repo path,
    optional docs-repo/changelog context for its time period
  Each agent: br update <id> --status in_progress → research → br close <id>
  Each agent returns structured JSON report
        │
        ▼
[Phase 3: Narrative Synthesis]
  Skill dispatches narrative-synthesizer agent
  Receives: all era JSON reports, project metadata
  Produces: TimelineJS3-format JSON with headlines, narratives, media refs
        │
        ▼
[Phase 4: Timeline Generation]
  scripts/generate-timeline.sh assembles output directory
  Copies vendored TimelineJS3 assets, injects timeline-data.json
  Output: self-contained storyteller-output/ directory
```

### Agent Design

**era-researcher** — Receives a single era (start/end boundaries) and performs layered analysis:

- Layer 1 (metadata baseline): commit count, date range, contributors, files added/removed/modified, commit message themes via `git log --stat` and `git shortlog`
- Layer 2 (selective deep-dive): identifies most impactful commits (large diffs, new directories, commits with keywords like "refactor"/"rewrite"/"migrate"/"breaking"), reads actual source to produce narrative descriptions
- Self-limits to ~50 most impactful commits per era to stay within context bounds
- If docs-repo or changelog provided, correlates documentation changes from the same time period
- Tools: Read, Grep, Glob, Bash (for git commands)

**narrative-synthesizer** — Receives all era reports and produces the final timeline:

- Identifies cross-era arcs ("started as CLI, pivoted to web service, added API layer")
- Writes headline + 2-3 paragraph summary per slide
- Selects media references per slide (GitHub URLs, contributor avatars)
- Generates title slide with project overview
- Produces TimelineJS3 JSON matching the `events` array format
- Tools: Read, Bash

### Beads Integration

Beads (`br` CLI from beads_rust) serves as the full coordination hub:

- Skill runs `br init` in a workspace directory (target repo's `.beads/` if writable, otherwise temp directory in output path)
- Before Phase 2: `br create "Research era: <start> → <end>" --priority 1` for each era
- Era agents: `br update <id> --status in_progress` on start, `br close <id>` with findings on completion
- All `br` commands use `--json` for machine-parseable output
- Provides audit trail and enables resumability if a run is interrupted

### Supplementary Context Sources

Users can provide additional context to enrich era narratives:

- **Docs repo** (`--docs-repo <path>`): A separate documentation repository. The skill filters by date ranges matching each era and passes relevant doc changes to era agents.
- **Changelog** (`--changelog <path>`): CHANGELOG.md, HISTORY.md, etc. Parsed and correlated by version/date to era boundaries.
- **README snapshots**: The skill automatically extracts `git show <tag>:README.md` at each era boundary to track how the project described itself over time.

### TimelineJS3 Output

```
storyteller-output/
├── index.html          # Main page, loads TimelineJS3
├── timeline-data.json  # Generated event data
└── assets/
    ├── css/            # TimelineJS3 styles
    └── js/             # TimelineJS3 library (vendored, no CDN)
```

TimelineJS3 is vendored (bundled locally) so the output works offline with no external dependencies. The output directory is fully portable.

### TimelineJS3 JSON Contract

Each era maps to one TimelineJS3 slide:

```typescript
interface TimelineData {
  title: {
    text: { headline: string; text: string };  // Project name + overview
  };
  events: Array<{
    start_date: { year: number; month: number; day: number };
    end_date?: { year: number; month: number; day: number };
    text: { headline: string; text: string };   // Era title + narrative
    media?: { url: string; caption: string; credit: string };
    group?: string;                             // Optional era grouping
  }>;
}
```

## Existing Patterns

This is a greenfield project — no existing codebase patterns to follow.

The plugin follows Claude Code's standard plugin structure:
- `.claude-plugin/plugin.json` for manifest
- `agents/` for subagent definitions with YAML frontmatter + markdown body
- `skills/` for skill definitions with `SKILL.md` files
- Shell scripts for deterministic operations (era detection, HTML assembly)

Agent definitions follow Claude Code's agent format: YAML frontmatter specifying `name`, `description`, `tools`, and `model`, followed by a markdown system prompt.

## Implementation Phases

<!-- START_PHASE_1 -->
### Phase 1: Plugin Scaffold & Project Setup
**Goal:** Initialize the Claude Code plugin structure with manifest, empty skill/agent shells, and Node.js project for supporting scripts.

**Components:**
- `.claude-plugin/plugin.json` — plugin manifest with name, version, description
- `skills/analyze/SKILL.md` — stub orchestrator skill
- `agents/era-researcher.md` — stub agent definition
- `agents/narrative-synthesizer.md` — stub agent definition
- `package.json` — Node.js project with TimelineJS3 as vendored dependency
- `templates/timeline.html` — base HTML template

**Dependencies:** None (first phase)

**Done when:** Plugin loads in Claude Code via `claude --plugin-dir .`, skill appears in `/` autocomplete, `npm install` succeeds
<!-- END_PHASE_1 -->

<!-- START_PHASE_2 -->
### Phase 2: Era Detection
**Goal:** Detect era boundaries from a target repository's git history using tags, time gaps, or commit counts.

**Components:**
- `scripts/detect-eras.sh` — shell script that analyzes git history and outputs JSON array of era objects with start/end boundaries, commit counts, date ranges
- Era detection logic: tags-first, time-gap fallback, commit-count fallback
- `skills/analyze/SKILL.md` — updated to run era detection, present results to user, accept overrides

**Dependencies:** Phase 1 (plugin structure exists)

**Done when:** Running era detection against a real repository with tags produces correct era boundaries; running against a tagless repo falls back to heuristics; user can see and override detected eras
<!-- END_PHASE_2 -->

<!-- START_PHASE_3 -->
### Phase 3: Beads Integration
**Goal:** Initialize Beads workspace and create/manage issues for era tracking.

**Components:**
- Beads initialization logic in `skills/analyze/SKILL.md` — `br init`, issue creation per era
- Workspace selection logic: use target repo's `.beads/` if writable, otherwise temp directory
- `skills/analyze/SKILL.md` — updated to create Beads issues after era confirmation

**Dependencies:** Phase 2 (eras detected and confirmed)

**Done when:** After era detection, Beads issues are created for each era; `br list --json` shows all era issues in pending state
<!-- END_PHASE_3 -->

<!-- START_PHASE_4 -->
### Phase 4: Era Researcher Agent
**Goal:** Build the era-researcher agent that performs layered analysis (metadata + selective deep-dive) on a single era.

**Components:**
- `agents/era-researcher.md` — full agent definition with system prompt covering:
  - Layer 1 metadata collection (git log, shortlog, diff stats)
  - Layer 2 selective deep-dive (impactful commit identification, source code reading)
  - Beads status updates (in_progress on start, close with findings)
  - Structured JSON output format
  - Self-limiting to ~50 impactful commits
- Supplementary context handling: docs-repo correlation, changelog parsing, README snapshots

**Dependencies:** Phase 3 (Beads issues exist for agent to update)

**Done when:** A single era-researcher agent, given era boundaries and a Beads issue ID, produces a structured JSON report with metadata stats and narrative summary; Beads issue is closed with findings
<!-- END_PHASE_4 -->

<!-- START_PHASE_5 -->
### Phase 5: Parallel Fan-Out Orchestration
**Goal:** The main skill fans out parallel Task calls to era-researcher agents and collects results.

**Components:**
- `skills/analyze/SKILL.md` — updated with Phase 2 orchestration: parallel Task tool calls (one per era), result collection, partial failure handling
- Error handling: failed agents are reported, successful results continue through pipeline

**Dependencies:** Phase 4 (era-researcher agent works for a single era)

**Done when:** Skill successfully fans out to multiple era-researcher agents in parallel, collects all results, handles partial failures gracefully
<!-- END_PHASE_5 -->

<!-- START_PHASE_6 -->
### Phase 6: Narrative Synthesizer Agent
**Goal:** Build the narrative-synthesizer agent that combines era reports into a cohesive TimelineJS3 JSON structure.

**Components:**
- `agents/narrative-synthesizer.md` — full agent definition with system prompt covering:
  - Cross-era arc identification
  - Headline and summary generation per slide
  - Media reference selection
  - Title slide generation
  - TimelineJS3 JSON output matching the contract

**Dependencies:** Phase 5 (era reports are collected and available)

**Done when:** Given a set of era JSON reports, the synthesizer produces valid TimelineJS3 JSON with title slide and one event per era; JSON validates against TimelineJS3's expected format
<!-- END_PHASE_6 -->

<!-- START_PHASE_7 -->
### Phase 7: Timeline HTML Generation
**Goal:** Assemble the final self-contained HTML output directory from the synthesizer's JSON.

**Components:**
- `scripts/generate-timeline.sh` — copies vendored TimelineJS3 assets, injects timeline-data.json, generates index.html from template
- `templates/timeline.html` — HTML template that loads TimelineJS3 and renders from timeline-data.json
- Vendored TimelineJS3 assets in `templates/assets/`

**Dependencies:** Phase 6 (TimelineJS3 JSON is produced)

**Done when:** Output directory contains working index.html that renders the timeline in a browser; works offline (no CDN dependencies); output is fully portable
<!-- END_PHASE_7 -->

<!-- START_PHASE_8 -->
### Phase 8: End-to-End Integration & Polish
**Goal:** Wire all phases together into the complete `/storyteller:analyze` flow and handle edge cases.

**Components:**
- `skills/analyze/SKILL.md` — complete orchestrator connecting all phases sequentially
- End-to-end flow: invocation → era detection → user override → Beads init → parallel research → synthesis → HTML generation → user report
- Edge case handling: repos with no tags, very large eras (500+ commits), read-only repos, docs-repo with different branch structure
- Final user output message with timeline location, era count, contributor count

**Dependencies:** Phase 7 (all individual components work)

**Done when:** Running `/storyteller:analyze` against a real repository with tags produces a working timeline webpage; running against a tagless repo also works; supplementary context (docs-repo, changelog) enriches the output when provided
<!-- END_PHASE_8 -->

## Additional Considerations

**Partial failures:** If some era-researcher agents fail (timeout, context overflow), the skill generates the timeline with available data and reports which eras failed with suggested remediation (e.g., "Era 4 failed — consider splitting its 500+ commits into sub-eras").

**Context limits:** Era-researcher agents self-limit to ~50 most impactful commits. The metadata layer still covers the full era regardless. For repos with very large eras, the skill could suggest finer-grained era boundaries.

**Beads workspace location:** If the target repo is read-only or already has a `.beads/` directory for other purposes, the skill creates a temporary Beads workspace in the output directory.

**Docs-repo correlation:** Matching documentation changes to code eras uses date-range filtering (`git log --after --before`) rather than tag matching, since docs repos often have different tagging schemes.

**TimelineJS3 slide limit:** The design targets ~20 eras maximum per the ~20-slide performance recommendation. Era detection heuristics should cluster or merge to stay within this bound.
