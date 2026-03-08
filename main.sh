#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# claude-sandbox-builder
#
# Given a GitHub repo URL, this script:
#   1. Clones the repo
#   2. Installs dependencies and builds the project
#   3. Generates a Dockerfile that bakes the build output + Claude Code CLI
#      + a custom CLAUDE.md into a fully-featured Debian image
#   4. Builds the Docker image
#   5. Runs a multi-agent analysis pipeline
#
# Usage:
#   ./main.sh <github-repo-url> [--fresh]
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/docker.sh"
source "$SCRIPT_DIR/lib/pipeline.sh"

# ── Defaults ────────────────────────────────────────────────────────────────
REPO_URL=""
IMAGE_TAG=""
CLAUDE_MD="$SCRIPT_DIR/prompts/CLAUDE.md"
BUILD_DIR=""
NODE_VERSION="20"
WORKDIR="/home/claude/repo_build_files"
CLAUDE_MODEL="opus"
FRESH=false

# ── Parse args ──────────────────────────────────────────────────────────────
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

# ── Derive repo name and output dirs ────────────────────────────────────────
REPO_NAME=$(basename "$REPO_URL" .git)
IMAGE_TAG="build-analysis-${REPO_NAME,,}"

log "Repo:  $REPO_URL"
log "Tag:   $IMAGE_TAG"
log ""

REPO_OUTPUT_DIR="$SCRIPT_DIR/output/${REPO_NAME,,}"
OUTPUT_DIR="$REPO_OUTPUT_DIR/src"
DOCS_DIR="$REPO_OUTPUT_DIR/docs"
STAGE_FILE="$DOCS_DIR/.stage"

if [[ "$FRESH" == true ]] && [[ -d "$REPO_OUTPUT_DIR" ]]; then
    warn "Removing previous output: $REPO_OUTPUT_DIR"
    rm -rf "$REPO_OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR" "$DOCS_DIR"

# ── Check if we can skip the build ──────────────────────────────────────────
NEEDS_BUILD=true
if [[ "$FRESH" != true ]] && [[ -f "$STAGE_FILE" ]] && docker image inspect "$IMAGE_TAG" > /dev/null 2>&1; then
    log "Image exists and previous run found — skipping build"
    NEEDS_BUILD=false
fi

STAGING_DIR=$(mktemp -d "$SCRIPT_DIR/.staging.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT

# ── Build phase ─────────────────────────────────────────────────────────────
if [[ "$NEEDS_BUILD" == true ]]; then
    log "Cloning $REPO_URL ..."
    git clone --depth 1 "$REPO_URL" "$STAGING_DIR/repo"
    ok "Cloned into $STAGING_DIR/repo"

    detect_package_manager "$STAGING_DIR/repo"

    log "Running: $PM_INSTALL"
    ( cd "$STAGING_DIR/repo" && eval "$PM_INSTALL" )
    ok "Dependencies installed"

    # Prisma: generate client if schema exists
    if [[ -f "$STAGING_DIR/repo/prisma/schema.prisma" ]] || [[ -d "$STAGING_DIR/repo/prisma/schema" ]]; then
        log "Prisma schema detected — running prisma generate"
        ( cd "$STAGING_DIR/repo" && npx prisma generate )
        ok "Prisma client generated"
    fi

    detect_build_cmd "$STAGING_DIR/repo"

    log "Running: $BUILD_CMD"
    ( cd "$STAGING_DIR/repo" && eval "$BUILD_CMD" )
    ok "Build complete"

    detect_build_output "$STAGING_DIR/repo"
    ok "Build output: $BUILD_DIR"

    # ── Resolve CLAUDE.md ────────────────────────────────────────────────────
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

    # ── Copy artifacts to staging ────────────────────────────────────────────
    cp -r "$STAGING_DIR/repo/$BUILD_DIR" "$STAGING_DIR/build-output"
    if [[ -f "$STAGING_DIR/repo/package.json" ]]; then
        cp "$STAGING_DIR/repo/package.json" "$STAGING_DIR/package.json"
    else
        echo '{}' > "$STAGING_DIR/package.json"
    fi
    cp -r "$SCRIPT_DIR/prompts" "$STAGING_DIR/prompts"

    prepare_docker_context
    build_docker_image

    # Persist clone for resume
    cp -r "$STAGING_DIR/repo" "$REPO_OUTPUT_DIR/.repo"
    ok "Repo cached for resume"
fi

# ── Resolve repo path (staging on fresh build, cached on resume) ────────────
if [[ -d "$STAGING_DIR/repo" ]]; then
    REPO_DIR="$STAGING_DIR/repo"
elif [[ -d "$REPO_OUTPUT_DIR/.repo" ]]; then
    REPO_DIR="$REPO_OUTPUT_DIR/.repo"
else
    REPO_DIR=""
fi

log "Output: $REPO_OUTPUT_DIR"

# ── Run pipeline ────────────────────────────────────────────────────────────
setup_container
detect_stage
run_pipeline
print_completion_banner "$REPO_OUTPUT_DIR"
