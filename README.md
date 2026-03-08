# Build Analyser

Analyses your codebase by rebuilding it from scratch. A multi-agent Claude Code pipeline reconstructs your source from its build output, then compares the reconstruction against the original to surface dead code, unnecessary abstractions, and structural improvements.

## Quick start

```bash
./main.sh https://github.com/user/repo
```

## What you get

Output appears in `output/<repo>/`:

```
output/my-app/
├── src/           Reconstructed source code
└── docs/
    ├── PLAN.md       Agent's analysis of the build output and reconstruction strategy
    ├── FOLLOWUP.md   Remaining work identified after first-pass review
    ├── MAPPING.md    File-by-file comparison of reconstructed vs original source
    └── REPORT.md     Code quality findings and improvement recommendations
```

The interesting signal is in the differences. Where the reconstruction diverges from the original, those are the places where your code has dead code the agent didn't reproduce, abstractions it simplified, or patterns it chose to do differently.

## How it works

1. Clones, builds, and strips source maps from your repo
2. Packages the build output into a sandboxed Docker container with Claude Code
3. A **planner** agent analyses the build output and creates a reconstruction strategy
4. A **worker** agent reconstructs the source code from the compiled output
5. The planner reviews the work and produces a follow-up plan; the worker executes it
6. A **reporter** agent compares the reconstruction against the original and writes findings

Each agent runs in an isolated container with no access to the original source until the final comparison step.

## Resuming

The pipeline tracks progress via a stage file. If a run fails or is interrupted, re-run the same command and it picks up where it left off:

```bash
./main.sh https://github.com/user/repo          # resumes automatically
./main.sh https://github.com/user/repo --fresh   # start over
```

## Requirements

- Docker
- Git
- Node.js + npm/pnpm/yarn/bun
- [gum](https://github.com/charmbracelet/gum) and [glow](https://github.com/charmbracelet/glow)
- Claude Code credentials (`~/.claude` and `~/.claude.json`)

## Project structure

```
main.sh                  Entry point + orchestration
sandbox.Dockerfile       Docker image (Debian + Node + Claude Code)
lib/
├── logging.sh           Logging via gum, agent helpers, banner
├── detect.sh            Package manager, build command, output directory detection
├── docker.sh            Image build, container lifecycle, run_claude helper
├── strip-sourcemaps.sh  Remove .map files, inline maps, sourceMappingURL comments
└── pipeline.sh          Stage definitions and pipeline runner
prompts/                 Agent prompts (one per step)
```

The pipeline is defined as a `STAGES` array in `pipeline.sh`. To add a stage, add its name to the array and write a `stage_*` function. Stages can be reordered or commented out.
