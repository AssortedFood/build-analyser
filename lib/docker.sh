#!/usr/bin/env bash
# lib/docker.sh — Dockerfile generation, image build, container lifecycle

# generate_dockerfile
# Uses globals: STAGING_DIR, REPO_URL, NODE_VERSION, WORKDIR
generate_dockerfile() {
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
}

# build_docker_image
# Uses globals: IMAGE_TAG, STAGING_DIR
build_docker_image() {
    log "Building Docker image: $IMAGE_TAG ..."
    docker build -t "$IMAGE_TAG" "$STAGING_DIR"
    ok "Image built: $IMAGE_TAG"
}

# setup_container
# Uses globals: REPO_NAME, IMAGE_TAG, OUTPUT_DIR, DOCS_DIR, STAGING_DIR
# Sets: CONTAINER_NAME, CLAUDE, PLANNER_SESSION, WORKER_SESSION, REPORTER_SESSION
setup_container() {
    CONTAINER_NAME="build-analysis-run-${REPO_NAME,,}"
    CLAUDE="claude --dangerously-skip-permissions --model opus"

    PLANNER_SESSION="$(cat /proc/sys/kernel/random/uuid)"
    WORKER_SESSION="$(cat /proc/sys/kernel/random/uuid)"
    REPORTER_SESSION="$(cat /proc/sys/kernel/random/uuid)"

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
}

# run_claude <args...>
# Uses globals: CONTAINER_NAME, CLAUDE
run_claude() {
    docker exec -t "$CONTAINER_NAME" $CLAUDE --verbose --output-format stream-json "$@" \
        | grep --line-buffered '^\{' \
        | jq --unbuffered -rj 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | "\n" + .text'
    echo ""
}

# run_bash <command>
# Uses globals: CONTAINER_NAME
run_bash() {
    docker exec -it "$CONTAINER_NAME" bash -c "$*"
}
