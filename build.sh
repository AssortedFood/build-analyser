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
#   ./build.sh <github-repo-url> [--fresh]
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

# ── Resolve script directory ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
REPO_URL=""
IMAGE_TAG=""  # set after repo name is derived
CLAUDE_MD="$SCRIPT_DIR/prompts/CLAUDE.md"
BUILD_DIR=""
BUILD_CMD="npm run build"
NODE_VERSION="20"
WORKDIR="/home/claude/repo_build_files"
FRESH=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            sed -n '/^# Usage:/,/^# ─/p' "$0" | head -n -1 | sed 's/^# //'
            exit 0
            ;;
        --fresh)
            FRESH=true; shift ;;
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
IMAGE_TAG="build-analysis-${REPO_NAME,,}"

log "Repo:  $REPO_URL"
log "Tag:   $IMAGE_TAG"

# ── Set up staging area ──────────────────────────────────────────────────────
STAGING_DIR=$(mktemp -d "${HOME}/.build-analysis-staging.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT  # updated later to also clean up container

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

# ── Copy prompt files to staging ─────────────────────────────────────────────
cp -r "$SCRIPT_DIR/prompts" "$STAGING_DIR/prompts"

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

# ── Empty src and docs directories ─────────────────────────────────────────
RUN mkdir -p ${WORKDIR}/src ${WORKDIR}/docs && chown claude:claude ${WORKDIR}/src ${WORKDIR}/docs

# ── Prompt files ───────────────────────────────────────────────────────────
COPY --chown=claude:claude prompts/ ${WORKDIR}/prompts/

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
REPO_OUTPUT_DIR="$SCRIPT_DIR/output/${REPO_NAME,,}"
OUTPUT_DIR="$REPO_OUTPUT_DIR/src"
DOCS_DIR="$REPO_OUTPUT_DIR/docs"
if [[ "$FRESH" == true ]] && [[ -d "$REPO_OUTPUT_DIR" ]]; then
    warn "Removing previous output: $REPO_OUTPUT_DIR"
    rm -rf "$REPO_OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR" "$DOCS_DIR"
log "Output: $REPO_OUTPUT_DIR"

CONTAINER_NAME="build-analysis-run-${REPO_NAME,,}"
CLAUDE="claude --dangerously-skip-permissions --model opus"

# Session IDs for each agent so we can resume specific conversations
PLANNER_SESSION="$(cat /proc/sys/kernel/random/uuid)"
WORKER_SESSION="$(cat /proc/sys/kernel/random/uuid)"
REPORTER_SESSION="$(cat /proc/sys/kernel/random/uuid)"

# ── Start persistent container ──────────────────────────────────────────────
log "Starting container: $CONTAINER_NAME ..."
docker run -d --name "$CONTAINER_NAME" \
    -e CLAUDE_CODE_EFFORT_LEVEL=high \
    -v "$OUTPUT_DIR:/home/claude/repo_build_files/src" \
    -v "$DOCS_DIR:/home/claude/repo_build_files/docs" \
    -v "$HOME/.claude:/home/claude/.claude" \
    -v "$HOME/.claude.json:/home/claude/.claude.json" \
    "$IMAGE_TAG" sleep infinity
trap 'docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1; rm -rf "$STAGING_DIR"' EXIT
ok "Container running"

run_claude() {
    docker exec -t "$CONTAINER_NAME" $CLAUDE --verbose --output-format stream-json "$@" \
        | grep --line-buffered '^\{' \
        | jq --unbuffered -rj 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | "\n" + .text'
    echo ""
}

run_bash() {
    docker exec -it "$CONTAINER_NAME" bash -c "$*"
}

# ── Agent log helpers ────────────────────────────────────────────────────────
planner() { echo -e "${CYAN}[planner]${NC} $*"; }
worker()  { echo -e "${CYAN}[worker ]${NC} $*"; }
reporter(){ echo -e "${CYAN}[reporter]${NC} $*"; }

# ── Stage detection ─────────────────────────────────────────────────────────
STAGE_FILE="$DOCS_DIR/.stage"
CURRENT_STAGE="start"
if [[ -f "$STAGE_FILE" ]]; then
    CURRENT_STAGE=$(cat "$STAGE_FILE")
    if [[ "$CURRENT_STAGE" == "complete" ]]; then
        ok "Pipeline already complete. Delete $STAGE_FILE to re-run."
        exit 0
    fi
    log "Resuming from stage: $CURRENT_STAGE"
fi

# ── Stage: plan (steps 1+2) ─────────────────────────────────────────────────
if [[ "$CURRENT_STAGE" == "start" ]]; then
    planner "Step 1/9: Creating plan ..."
    run_claude --session-id "$PLANNER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/01-plan.md")"
    ok "Plan created"

    planner "Step 2/9: Reviewing plan ..."
    run_claude --resume "$PLANNER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/02-plan-review.md")"
    ok "Plan reviewed"

    echo "planned" > "$STAGE_FILE"
    CURRENT_STAGE="planned"
fi

# ── Stage: work (step 3) ────────────────────────────────────────────────────
if [[ "$CURRENT_STAGE" == "planned" ]]; then
    worker "Step 3/9: Executing plan ..."
    run_claude --session-id "$WORKER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/03-worker-execute.md")"
    ok "Worker finished"

    echo "worked" > "$STAGE_FILE"
    CURRENT_STAGE="worked"
fi

# ── Stage: review (steps 4+5) ───────────────────────────────────────────────
if [[ "$CURRENT_STAGE" == "worked" ]]; then
    planner "Step 4/9: Reviewing work ..."
    run_claude --session-id "$PLANNER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/04-review-work.md")"
    ok "Work reviewed"

    planner "Step 5/9: Creating follow-up plan ..."
    run_claude --resume "$PLANNER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/05-followup-plan.md")"
    ok "Follow-up plan created"

    echo "reviewed" > "$STAGE_FILE"
    CURRENT_STAGE="reviewed"
fi

# ── Stage: followup (step 6) ────────────────────────────────────────────────
if [[ "$CURRENT_STAGE" == "reviewed" ]]; then
    worker "Step 6/9: Executing follow-up ..."
    run_claude --session-id "$WORKER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/06-worker-followup.md")"
    ok "Worker follow-up finished"

    echo "followed_up" > "$STAGE_FILE"
    CURRENT_STAGE="followed_up"
fi

# ── Stage: report (steps 7+8+9) ─────────────────────────────────────────────
if [[ "$CURRENT_STAGE" == "followed_up" ]]; then
    log "Step 7/9: Copying original source into container ..."
    docker cp "$STAGING_DIR/repo" "$CONTAINER_NAME:/home/claude/repo_build_files/original_src"
    docker exec "$CONTAINER_NAME" chown -R claude:claude /home/claude/repo_build_files/original_src
    ok "Original source copied"

    reporter "Step 8/9: Producing mapping ..."
    run_claude --session-id "$REPORTER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/07-reporter-mapping.md")"
    ok "Mapping complete"

    reporter "Step 9/9: Producing report ..."
    run_claude --resume "$REPORTER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/08-reporter-report.md")"
    ok "Report complete"

    echo "complete" > "$STAGE_FILE"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Pipeline complete!${NC}"
echo -e "${GREEN}  Output: $REPO_OUTPUT_DIR${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
