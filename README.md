# Storyteller

A Claude Code plugin that turns a git repository's commit history into an interactive [TimelineJS3](https://timeline.knightlab.com/) timeline. It analyzes eras of development via parallel AI agents and synthesizes narrative-driven visual output.

## Goals

- **Make git history human-readable.** Transform raw commits into a visual story with compelling headlines and narrative prose.
- **Work on any repository.** Automatically detect eras using tags, time gaps, or commit-count chunking — no configuration required.
- **Produce portable output.** Generate a self-contained HTML directory with vendored assets that works offline, with no CDN dependencies.
- **Scale via parallelism.** Fan out independent era research to parallel subagents, each with its own context window, so large repositories don't overflow a single session.
- **Support incremental runs.** Track progress via Beads issue tracking so interrupted runs can resume where they left off.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [Node.js](https://nodejs.org/) (for TimelineJS3 vendoring)
- [`jq`](https://jqlang.github.io/jq/) (used by era detection script)
- [`br`](https://github.com/qdot/beads) (Beads CLI, for issue tracking coordination)

## Installation

```bash
git clone <this-repo> storyteller
cd storyteller
npm install
```

## Usage

Load the plugin and invoke the analyze skill:

```bash
claude --plugin-dir /path/to/storyteller
```

Then within a Claude Code session:

```
/storyteller:analyze [repo-path] [--docs-repo <path>] [--changelog <path>] [--output <path>]
```

### Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `repo-path` | Path to the git repository to analyze | Current working directory |
| `--docs-repo <path>` | Separate documentation repository for supplementary context | — |
| `--changelog <path>` | Changelog file (CHANGELOG.md, HISTORY.md, etc.) | — |
| `--output <path>` | Output directory for the generated timeline | `./storyteller-output/` |

### Example

```bash
# Analyze a local repository
/storyteller:analyze /path/to/my-project

# With supplementary context
/storyteller:analyze /path/to/my-project --docs-repo /path/to/docs --changelog /path/to/CHANGELOG.md

# Custom output location
/storyteller:analyze /path/to/my-project --output /tmp/my-timeline
```

After completion, open `storyteller-output/index.html` in a browser to view the interactive timeline.

## How It Works

The plugin runs six phases sequentially:

1. **Era Detection** — Identifies time periods in the repository using tags, 90-day inactivity gaps, or commit-count chunking (capped at 20 eras). Presents results for user confirmation.
2. **Beads Initialization** — Creates a local issue tracker to coordinate agent work and support resume on interrupted runs.
3. **Parallel Era Research** — Fans out one `era-researcher` subagent per era, all running concurrently. Each agent performs a two-layer analysis: aggregate metadata (commit counts, contributors, file changes) followed by selective deep-dives into the most impactful commits.
4. **Narrative Synthesis** — A `narrative-synthesizer` subagent combines all era reports into TimelineJS3 JSON, writing compelling headlines and storytelling prose for each era.
5. **Timeline Generation** — Assembles a self-contained HTML directory with vendored TimelineJS3 assets and the generated timeline data.
6. **Final Report** — Summarizes results and provides the path to the generated timeline.

## Project Structure

```
.claude-plugin/plugin.json    Plugin manifest
skills/analyze/SKILL.md       Main orchestrator skill
agents/era-researcher.md      Subagent: analyzes a single era
agents/narrative-synthesizer.md  Subagent: combines era reports into TimelineJS3 JSON
scripts/detect-eras.sh        Era boundary detection (bash + jq)
scripts/generate-timeline.sh  HTML output assembly
templates/timeline.html       TimelineJS3 viewer template
```

## License

See LICENSE file for details.
