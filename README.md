# build-analyser

Automates building isolated Docker environments with Claude Code + your project's build output + a custom `CLAUDE.md` instruction set.

## What it does

1. Clones a GitHub repo (shallow)
2. Detects package manager (npm/pnpm/yarn/bun) and installs dependencies
3. Runs `npm run build`
4. Auto-detects the build output directory (`dist`, `build`, `out`, `.next`, etc.)
5. Generates a Dockerfile (Debian Bookworm with a full toolchain)
6. Bakes in the build output, Claude Code CLI, and `CLAUDE.md`
7. Builds the Docker image

## Quick start

```bash
chmod +x build.sh
./build.sh https://github.com/user/repo
```

## Running the sandbox

```bash
# Interactive shell, then run `claude` manually
docker run -it --rm -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY ba-myrepo

# Launch Claude Code directly
docker run -it --rm -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY ba-myrepo claude

# Autonomous mode (skips permission prompts)
docker run -it --rm -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY ba-myrepo claude --dangerously-skip-permissions

# Mount a volume to extract outputs
docker run -it --rm \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -v $(pwd)/output:/home/claude/repo_build_files/output \
  ba-myrepo
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
