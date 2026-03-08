# CLAUDE.md

## Environment

You are inside an isolated Docker container (Debian Bookworm).
Your working directory is `~/repo_build_files/`.

- `build/` — the project's compiled build output
- `src/` — empty directory for reconstructed source
- `docs/` — directory for plans, reports, and other documentation

## Tools

- Node.js, npm, Python 3
- git, curl, jq, ripgrep, fd-find, bat
- gcc, g++, make

## Task

Analyse the build output in `build/` and reconstruct the original source code into `src/`.
