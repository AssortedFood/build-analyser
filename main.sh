#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# claude-sandbox-builder
#
# Given a GitHub repo URL, this script:
#   1. Clones the repo
#   2. Installs dependencies and builds the project
#   3. Builds a Docker image with the build output + Claude Code CLI
#   4. Runs a multi-agent analysis pipeline
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

REPO_OUTPUT_DIR="$SCRIPT_DIR/output/${REPO_NAME,,}"
OUTPUT_DIR="$REPO_OUTPUT_DIR/src"
DOCS_DIR="$REPO_OUTPUT_DIR/docs"
STAGE_FILE="$REPO_OUTPUT_DIR/.stage"

if [[ "$FRESH" == true ]] && [[ -d "$REPO_OUTPUT_DIR" ]]; then
    warn "Removing previous output: $REPO_OUTPUT_DIR"
    rm -rf "$REPO_OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR" "$DOCS_DIR"

# ── Staging dir for docker context ──────────────────────────────────────────
STAGING_DIR=$(mktemp -d "$SCRIPT_DIR/.staging.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT

# ── Run ─────────────────────────────────────────────────────────────────────
detect_stage
run_pipeline
print_completion_banner "$REPO_OUTPUT_DIR"
