#!/usr/bin/env bash
# lib/docker.sh — Dockerfile generation, image build, container lifecycle

# prepare_docker_context
# Uses globals: STAGING_DIR, SCRIPT_DIR
prepare_docker_context() {
    cp "$SCRIPT_DIR/sandbox.Dockerfile" "$STAGING_DIR/Dockerfile"
    ok "Dockerfile copied to staging"
}

# build_docker_image
# Uses globals: IMAGE_TAG, STAGING_DIR, NODE_VERSION, WORKDIR
build_docker_image() {
    log "Building Docker image: $IMAGE_TAG ..."
    docker build \
        --build-arg NODE_VERSION="$NODE_VERSION" \
        --build-arg WORKDIR="$WORKDIR" \
        -t "$IMAGE_TAG" "$STAGING_DIR"
    ok "Image built: $IMAGE_TAG"
}

# setup_container
# Uses globals: REPO_NAME, IMAGE_TAG, OUTPUT_DIR, DOCS_DIR, STAGING_DIR, WORKDIR, CLAUDE_MODEL
# Sets: CONTAINER_NAME, CLAUDE, PLANNER_SESSION, WORKER_SESSION, REPORTER_SESSION
CONTAINER_RUNNING=false
setup_container() {
    CONTAINER_NAME="build-analysis-run-${REPO_NAME,,}"
    CLAUDE="claude --dangerously-skip-permissions --model $CLAUDE_MODEL"

    PLANNER_SESSION="$(cat /proc/sys/kernel/random/uuid)"
    WORKER_SESSION="$(cat /proc/sys/kernel/random/uuid)"
    REPORTER_SESSION="$(cat /proc/sys/kernel/random/uuid)"

    log "Starting container: $CONTAINER_NAME ..."
    docker run -d --name "$CONTAINER_NAME" \
        -e CLAUDE_CODE_EFFORT_LEVEL=high \
        -v "$OUTPUT_DIR:$WORKDIR/src" \
        -v "$DOCS_DIR:$WORKDIR/docs" \
        -v "$HOME/.claude:/home/claude/.claude" \
        -v "$HOME/.claude.json:/home/claude/.claude.json" \
        "$IMAGE_TAG" sleep infinity
    trap 'docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1; rm -rf "$STAGING_DIR"' EXIT
    CONTAINER_RUNNING=true
    ok "Container running"
}

# ensure_container — lazily starts the container on first agent stage
ensure_container() {
    [[ "$CONTAINER_RUNNING" == true ]] && return
    setup_container
}

# run_claude <args...>
# Uses globals: CONTAINER_NAME, CLAUDE
run_claude() {
    docker exec -t "$CONTAINER_NAME" $CLAUDE --verbose --output-format stream-json "$@" \
        | grep --line-buffered '^\{' \
        | jq --unbuffered -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | "\u200B\n" + .text'
    echo ""
}

# run_bash <command>
# Uses globals: CONTAINER_NAME
run_bash() {
    docker exec -it "$CONTAINER_NAME" bash -c "$*"
}
