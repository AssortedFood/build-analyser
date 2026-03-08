# build-analyser

Clones a GitHub repo, builds it, and runs a multi-agent Claude Code pipeline that reconstructs the original source from the build output, then compares the reconstruction against the original.

## What it does

1. Clones a GitHub repo (shallow)
2. Detects package manager (npm/pnpm/yarn/bun) and installs dependencies
3. Detects and runs the project's build command
4. Auto-detects the build output directory (`dist`, `build`, `out`, `.next`, etc.)
5. Builds a Docker image with the build output, Claude Code CLI, and prompt files
6. Runs a multi-agent analysis pipeline inside the container

## Pipeline

| Step | Stage | Description |
|------|-------|-------------|
| 1 | clone | Clones the repo (shallow) |
| 2 | install | Detects package manager, installs dependencies |
| 3 | build | Detects and runs the build command |
| 4 | strip | Removes source maps from build output |
| 5 | image | Creates Docker image with build output + Claude Code |
| 6 | plan | Planner analyses build output, creates `docs/PLAN.md` |
| 7 | plan | Planner sense-checks and fixes the plan |
| 8 | work | Worker executes the plan, reconstructs source into `src/` |
| 9 | review | Planner reviews worker's output, scores it /10 |
| 10 | review | Planner produces `docs/FOLLOWUP.md` for remaining work |
| 11 | followup | Worker executes the follow-up plan |
| 12 | report | Copies original repo into container as `original_src/` |
| 13 | report | Reporter compares `src/` vs `original_src/`, writes `docs/MAPPING.md` |
| 14 | report | Reporter writes `docs/REPORT.md` with improvement recommendations |

Agents run with **high thinking effort**. Model is configurable via `CLAUDE_MODEL` in `main.sh` (default: `opus`).

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
main.sh              Entry point + orchestration
sandbox.Dockerfile   Docker image definition (Debian + Node + Claude Code)
lib/
├── logging.sh       Logging via gum, agent helpers, banner
├── detect.sh        Package manager, build command, and output directory detection
├── docker.sh             Image build, container lifecycle, run_claude helper
├── strip-sourcemaps.sh   Remove .map files, inline maps, and sourceMappingURL comments
└── pipeline.sh           Modular stage definitions and pipeline runner
prompts/             Agent prompts (one per step)
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
- [glow](https://github.com/charmbracelet/glow) (for markdown rendering)
- Claude Code credentials (`~/.claude` and `~/.claude.json`)
