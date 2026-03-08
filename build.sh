#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# claude-sandbox-builder
#
# Given a GitHub repo URL, this script:
#   1. Clones the repo
#   2. Runs `npm install && npm run build`
#   3. Generates a Dockerfile that bakes the build output + Claude Code CLI
#      + a custom CLAUDE.md into a fully-featured Debian image
#   4. Builds the Docker image
#
# Usage:
#   ./build.sh <github-repo-url>
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[builder]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ warn ]${NC} $*"; }
err()  { echo -e "${RED}[error ]${NC} $*" >&2; }
die()  { err "$@"; exit 1; }

# ── Defaults ──────────────────────────────────────────────────────────────────
REPO_URL=""
IMAGE_TAG=""  # set after repo name is derived
CLAUDE_MD="./CLAUDE-to_copy.md"
BUILD_DIR=""
BUILD_CMD="npm run build"
NODE_VERSION="20"
WORKDIR="/home/claude/repo_build_files"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            sed -n '/^# Usage:/,/^# ─/p' "$0" | head -n -1 | sed 's/^# //'
            exit 0
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            [[ -z "$REPO_URL" ]] && REPO_URL="$1" || die "Unexpected argument: $1"
            shift
            ;;
    esac
done

[[ -z "$REPO_URL" ]] && die "Usage: $0 <github-repo-url>"

# ── Derive repo name and image tag ────────────────────────────────────────────
REPO_NAME=$(basename "$REPO_URL" .git)
IMAGE_TAG="ba-${REPO_NAME,,}"

log "Repo:  $REPO_URL"
log "Tag:   $IMAGE_TAG"

# ── Set up staging area ──────────────────────────────────────────────────────
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

log "Staging directory: $STAGING_DIR"

# ── Clone ─────────────────────────────────────────────────────────────────────
log "Cloning $REPO_URL ..."
git clone --depth 1 "$REPO_URL" "$STAGING_DIR/repo"
ok "Cloned into $STAGING_DIR/repo"

# ── Install + Build ──────────────────────────────────────────────────────────
cd "$STAGING_DIR/repo"

# Detect package manager
if [[ -f "pnpm-lock.yaml" ]]; then
    PM="pnpm"
    PM_INSTALL="pnpm install --frozen-lockfile"
elif [[ -f "yarn.lock" ]]; then
    PM="yarn"
    PM_INSTALL="yarn install --frozen-lockfile"
elif [[ -f "bun.lockb" ]] || [[ -f "bun.lock" ]]; then
    PM="bun"
    PM_INSTALL="bun install"
else
    PM="npm"
    PM_INSTALL="npm ci --ignore-scripts=false 2>/dev/null || npm install"
fi

log "Detected package manager: $PM"
log "Running: $PM_INSTALL"
eval "$PM_INSTALL"
ok "Dependencies installed"

log "Running: $BUILD_CMD"
eval "$BUILD_CMD"
ok "Build complete"

cd - > /dev/null

# ── Auto-detect build output directory ────────────────────────────────────
for candidate in dist build out .next output public/build; do
    if [[ -d "$STAGING_DIR/repo/$candidate" ]]; then
        BUILD_DIR="$candidate"
        break
    fi
done
[[ -z "$BUILD_DIR" ]] && die "Could not auto-detect build directory."

ok "Build output: $BUILD_DIR"

# ── Resolve CLAUDE.md ─────────────────────────────────────────────────────────
if [[ -f "$CLAUDE_MD" ]]; then
    cp "$CLAUDE_MD" "$STAGING_DIR/CLAUDE.md"
    ok "Using CLAUDE.md from: $CLAUDE_MD"
elif [[ -f "$STAGING_DIR/repo/CLAUDE.md" ]]; then
    cp "$STAGING_DIR/repo/CLAUDE.md" "$STAGING_DIR/CLAUDE.md"
    warn "No external CLAUDE.md found, using one from the repo"
else
    warn "No CLAUDE.md found. Creating a minimal placeholder."
    cat > "$STAGING_DIR/CLAUDE.md" <<'PLACEHOLDER'
# CLAUDE.md

You are working in a sandboxed environment with the build output of a project.
Explore the workspace to understand the project structure before making changes.
PLACEHOLDER
fi

# ── Copy build output to staging ──────────────────────────────────────────────
cp -r "$STAGING_DIR/repo/$BUILD_DIR" "$STAGING_DIR/build-output"

# Also grab package.json if it exists (useful context)
[[ -f "$STAGING_DIR/repo/package.json" ]] && cp "$STAGING_DIR/repo/package.json" "$STAGING_DIR/package.json"

# ── Generate Dockerfile ──────────────────────────────────────────────────────
cat > "$STAGING_DIR/Dockerfile" <<DOCKERFILE
# ─────────────────────────────────────────────────────────────────────────────
# claude-sandbox-builder: auto-generated Dockerfile
# Repo: ${REPO_URL}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ─────────────────────────────────────────────────────────────────────────────

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \\
    bash curl wget git jq tree unzip zip tar \\
    openssh-client ca-certificates gnupg sudo \\
    build-essential procps findutils diffutils \\
    ripgrep fd-find bat less vim nano \\
    python3 python3-pip python3-venv \\
    && rm -rf /var/lib/apt/lists/*

# ── Node.js ${NODE_VERSION} ─────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \\
    && apt-get install -y nodejs \\
    && rm -rf /var/lib/apt/lists/*

# ── Claude Code CLI ──────────────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code

# ── Workspace setup ──────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash -u 1000 claude \\
    && mkdir -p ${WORKDIR} \\
    && chown -R claude:claude ${WORKDIR}

WORKDIR ${WORKDIR}

# ── Copy build artifacts ─────────────────────────────────────────────────────
COPY --chown=claude:claude build-output/ ${WORKDIR}/build/
COPY --chown=claude:claude CLAUDE.md ${WORKDIR}/CLAUDE.md
$(if [[ -f "$STAGING_DIR/package.json" ]]; then echo "COPY --chown=claude:claude package.json ${WORKDIR}/package.json"; fi)

# ── Empty src directory for new work ────────────────────────────────────────
RUN mkdir -p ${WORKDIR}/src && chown claude:claude ${WORKDIR}/src

# ── Environment ──────────────────────────────────────────────────────────────
ENV LANG=C.UTF-8
ENV TERM=xterm-256color

USER claude

# Default: drop into bash so you can run claude interactively
CMD ["bash"]
DOCKERFILE

ok "Dockerfile generated"

# ── Build ─────────────────────────────────────────────────────────────────────
log "Building Docker image: $IMAGE_TAG ..."
docker build -t "$IMAGE_TAG" "$STAGING_DIR"
ok "Image built: $IMAGE_TAG"

echo ""
log "Launching container ..."
exec docker run -it --rm "$IMAGE_TAG"
