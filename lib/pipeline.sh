#!/usr/bin/env bash
# lib/pipeline.sh — Stage management and pipeline execution
#
# To customise the pipeline, edit the stage functions or reorder the STAGES array.
# Each stage_* function is self-contained. run_step handles the claude interaction.

# ── Pipeline definition ──────────────────────────────────────────────────────
# Reorder, comment out, or add stages here.
STAGES=(clone install build image plan work review followup report)

# ── Step runner ───────────────────────────────────────────────────────────────
STEP=0

# run_step <agent> <label> <session-mode> <session-id> <prompt-file>
#   agent:        planner | worker | reporter
#   label:        human-readable description
#   session-mode: session-id (new) | resume (continue)
#   prompt-file:  filename inside prompts/
run_step() {
    local agent="$1" label="$2" mode="$3" session="$4" prompt="$5"
    local color
    color=$(agent_color "$agent")

    STEP=$((STEP + 1))
    step_header "$color" "Step $STEP · $agent · $label"

    run_claude --"$mode" "$session" -p "$(cat "$SCRIPT_DIR/prompts/$prompt")" \
        | stamp_stream

    ok "$label"
}

# ── Build stages ──────────────────────────────────────────────────────────────
# REPO_DIR is set lazily — $REPO_OUTPUT_DIR isn't available at source time.

stage_clone() {
    STEP=$((STEP + 1))
    step_header 75 "Step $STEP · clone · Cloning repository"

    [[ -d "$REPO_DIR" ]] && rm -rf "$REPO_DIR"
    log "Cloning $REPO_URL ..."
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
    ok "Cloned into $REPO_DIR"
}

stage_install() {
    STEP=$((STEP + 1))
    step_header 75 "Step $STEP · install · Installing dependencies"

    detect_package_manager "$REPO_DIR"

    log "Running: $PM_INSTALL"
    ( cd "$REPO_DIR" && eval "$PM_INSTALL" )
    ok "Dependencies installed"

    # Prisma: generate client if schema exists
    if [[ -f "$REPO_DIR/prisma/schema.prisma" ]] || [[ -d "$REPO_DIR/prisma/schema" ]]; then
        log "Prisma schema detected — running prisma generate"
        ( cd "$REPO_DIR" && npx prisma generate )
        ok "Prisma client generated"
    fi
}

stage_build() {
    STEP=$((STEP + 1))
    step_header 75 "Step $STEP · build · Building project"

    detect_build_cmd "$REPO_DIR"

    log "Running: $BUILD_CMD"
    ( cd "$REPO_DIR" && eval "$BUILD_CMD" )
    ok "Build complete"
}

stage_image() {
    STEP=$((STEP + 1))
    step_header 75 "Step $STEP · image · Creating Docker image"

    detect_build_output "$REPO_DIR"
    ok "Build output: $BUILD_DIR"

    # Resolve CLAUDE.md
    if [[ -f "$CLAUDE_MD" ]]; then
        cp "$CLAUDE_MD" "$STAGING_DIR/CLAUDE.md"
        ok "Using CLAUDE.md from: $CLAUDE_MD"
    elif [[ -f "$REPO_DIR/CLAUDE.md" ]]; then
        cp "$REPO_DIR/CLAUDE.md" "$STAGING_DIR/CLAUDE.md"
        warn "No external CLAUDE.md found, using one from the repo"
    else
        warn "No CLAUDE.md found. Creating a minimal placeholder."
        cat > "$STAGING_DIR/CLAUDE.md" <<'PLACEHOLDER'
# CLAUDE.md

You are working in a sandboxed environment with the build output of a project.
Explore the workspace to understand the project structure before making changes.
PLACEHOLDER
    fi

    # Copy artifacts to staging
    cp -r "$REPO_DIR/$BUILD_DIR" "$STAGING_DIR/build-output"
    if [[ -f "$REPO_DIR/package.json" ]]; then
        cp "$REPO_DIR/package.json" "$STAGING_DIR/package.json"
    else
        echo '{}' > "$STAGING_DIR/package.json"
    fi
    cp -r "$SCRIPT_DIR/prompts" "$STAGING_DIR/prompts"

    prepare_docker_context
    build_docker_image
}

# ── Agent stages ──────────────────────────────────────────────────────────────

stage_plan() {
    ensure_container
    run_step planner "Creating plan"     session-id "$PLANNER_SESSION"  "01-plan.md"
    run_step planner "Reviewing plan"    resume     "$PLANNER_SESSION"  "02-plan-review.md"
}

stage_work() {
    ensure_container
    run_step worker "Executing plan"     session-id "$WORKER_SESSION"   "03-worker-execute.md"
}

stage_review() {
    ensure_container
    run_step planner "Reviewing work"        resume     "$PLANNER_SESSION"  "04-review-work.md"
    run_step planner "Creating follow-up"    resume     "$PLANNER_SESSION"  "05-followup-plan.md"
}

stage_followup() {
    ensure_container
    run_step worker "Executing follow-up"    session-id "$WORKER_SESSION"   "06-worker-followup.md"
}

stage_report() {
    ensure_container

    STEP=$((STEP + 1))
    step_header "$(agent_color reporter)" "Step $STEP · report · Copying original source"
    [[ ! -d "$REPO_DIR" ]] && die "No cached repo found for comparison."
    docker cp "$REPO_DIR" "$CONTAINER_NAME:$WORKDIR/original_src"
    docker exec "$CONTAINER_NAME" chown -R claude:claude "$WORKDIR/original_src"
    ok "Original source copied"

    run_step reporter "Producing mapping"    session-id "$REPORTER_SESSION" "07-reporter-mapping.md"
    run_step reporter "Producing report"     resume     "$REPORTER_SESSION" "08-reporter-report.md"
}

# ── Stage detection ───────────────────────────────────────────────────────────

# detect_stage
# Uses globals: STAGE_FILE
# Sets: CURRENT_STAGE
detect_stage() {
    CURRENT_STAGE="start"
    if [[ -f "$STAGE_FILE" ]]; then
        CURRENT_STAGE=$(cat "$STAGE_FILE")
        if [[ "$CURRENT_STAGE" == "complete" ]]; then
            ok "Pipeline already complete. Delete $STAGE_FILE to re-run."
            exit 0
        fi
        log "Resuming from stage: $CURRENT_STAGE"
    fi
}

# ── Pipeline runner ───────────────────────────────────────────────────────────

# run_pipeline
# Iterates STAGES, skips completed stages, runs remaining ones.
run_pipeline() {
    REPO_DIR="$REPO_OUTPUT_DIR/.repo"

    local started=false
    [[ "$CURRENT_STAGE" == "start" ]] && started=true

    for stage in "${STAGES[@]}"; do
        if [[ "$started" == true ]]; then
            "stage_$stage"
            echo "$stage" > "$STAGE_FILE"
        elif [[ "$CURRENT_STAGE" == "$stage" ]]; then
            started=true
        fi
    done

    echo "complete" > "$STAGE_FILE"
}
