# build-analyser

Clones a GitHub repo, builds it, and runs a multi-agent Claude Code pipeline that reconstructs the original source from the build output, then compares the reconstruction against the original.

## What it does

1. Clones a GitHub repo (shallow)
2. Detects package manager (npm/pnpm/yarn/bun) and installs dependencies
3. Runs `npm run build`
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
| 7 | *script* | Clones original repo into `original_src/` |
| 8 | Reporter | Compares `src/` vs `original_src/`, writes `docs/MAPPING.md` |
| 9 | Reporter | Writes `docs/REPORT.md` with improvement recommendations |

## Quick start

```bash
chmod +x build.sh
./build.sh https://github.com/user/repo
```

## Output

After the pipeline completes, output appears in `output/<repo>/`:

```
output/my-app/
├── src/    — the reconstructed source code
└── docs/   — PLAN.md, FOLLOWUP.md, MAPPING.md, REPORT.md
```

## Prompts

All agent prompts live in `prompts/` as separate markdown files. Edit them to change agent behaviour.

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
- Claude Code credentials (`~/.claude` and `~/.claude.json`)
