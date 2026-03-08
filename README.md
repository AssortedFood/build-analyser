# build-analyser

Clones a GitHub repo, builds it, and runs a multi-agent Claude Code pipeline that reconstructs the original source from the build output, then compares the reconstruction against the original.

## What it does

1. Clones a GitHub repo (shallow)
2. Detects package manager (npm/pnpm/yarn/bun) and installs dependencies
3. Detects and runs the project's build command
4. Auto-detects the build output directory (`dist`, `build`, `out`, `.next`, etc.)
5. Builds a Docker image with the build output, Claude Code CLI, and prompt files
6. Runs a 9-step agent pipeline inside the container

## Pipeline

| Step | Agent | Description |
|------|-------|-------------|
| 1 | Planner | Analyses build output, creates `docs/PLAN.md` |
| 2 | Planner | Sense-checks and fixes the plan |
| 3 | Worker | Executes the plan, reconstructs source into `src/` |
| 4 | Planner | Reviews worker's output, scores it /10 |
| 5 | Planner | Produces `docs/FOLLOWUP.md` for remaining work |
| 6 | Worker | Executes the follow-up plan |
| 7 | *script* | Copies original repo into container as `original_src/` |
| 8 | Reporter | Compares `src/` vs `original_src/`, writes `docs/MAPPING.md` |
| 9 | Reporter | Writes `docs/REPORT.md` with improvement recommendations |

All agents run on **Opus 4.6** with **high thinking effort**.

## Quick start

```bash
chmod +x main.sh
./main.sh https://github.com/user/repo
```

## Resuming

The pipeline tracks progress via a stage file (`output/<repo>/docs/.stage`). If a run fails or is interrupted, re-run the same command and it picks up where it left off:

```bash
# Resumes automatically from the last completed stage
./main.sh https://github.com/user/repo

# Start fresh (deletes previous output)
./main.sh https://github.com/user/repo --fresh
```

## Output

After the pipeline completes, output appears in `output/<repo>/`:

```
output/my-app/
├── src/    — the reconstructed source code
└── docs/   — PLAN.md, FOLLOWUP.md, MAPPING.md, REPORT.md
```

## Project structure

```
main.sh            Entry point + orchestration
lib/
├── logging.sh     Colors, log functions, agent helpers, banner
├── detect.sh      Package manager, build command, and output directory detection
├── docker.sh      Dockerfile generation, image build, container lifecycle
└── pipeline.sh    Stage management and pipeline execution
prompts/           Agent prompts (one per step)
```

## What's in the image

- **Debian Bookworm** (full-featured, not Alpine)
- **Node.js 20**
- **Claude Code CLI** (`@anthropic-ai/claude-code`)
- **Python 3** + pip + venv
- **Dev tools**: git, curl, wget, jq, tree, ripgrep, fd-find, bat, vim, nano
- **Build tools**: gcc, g++, make
- Non-root `claude` user (UID 1000)

## Requirements

- Docker
- Git
- Node.js + npm/pnpm/yarn (for the build step on the host)
- [gum](https://github.com/charmbracelet/gum) (for terminal UI)
- Claude Code credentials (`~/.claude` and `~/.claude.json`)
