# CLAUDE.md

## Environment

You are running inside an isolated Docker container (Debian Bookworm).
The project's build output is located at `/workspace/build/`.

## Available Tools

- Node.js and npm are installed globally
- Python 3 is available
- Standard unix tools: git, curl, jq, ripgrep, fd-find, bat, vim, nano
- Build tools: gcc, g++, make

## Guidelines

- Explore the build output to understand the project structure before making changes
- If you need additional packages, install them with `sudo apt-get install -y <pkg>` or `npm install <pkg>`
- Write any new files to `/workspace/output/` so they can be extracted via volume mount
- Be thorough in your analysis and concise in your responses
