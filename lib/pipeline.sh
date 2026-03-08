#!/usr/bin/env bash
# lib/pipeline.sh — Stage management and pipeline execution
#
# To customise the pipeline, edit the stage functions or reorder the STAGES array.
# Each stage_* function is self-contained. run_step handles the claude interaction.

# ── Pipeline definition ──────────────────────────────────────────────────────
# Reorder, comment out, or add stages here.
STAGES=(plan work review followup report)

# ── Step runner ───────────────────────────────────────────────────────────────
STEP=0

# run_step <agent> <label> <session-mode> <session-id> <prompt-file>
#   agent:        planner | worker | reporter
#   label:        human-readable description
#   session-mode: session-id (new) | resume (continue)
#   prompt-file:  filename inside prompts/
run_step() {
    local agent="$1" label="$2" mode="$3" session="$4" prompt="$5"
    ((STEP++))
    "$agent" "Step $STEP: $label ..."
    run_claude --"$mode" "$session" -p "$(cat "$SCRIPT_DIR/prompts/$prompt")"
    ok "$label"
}

# ── Stage definitions ─────────────────────────────────────────────────────────

stage_plan() {
    run_step planner "Creating plan"     session-id "$PLANNER_SESSION"  "01-plan.md"
    run_step planner "Reviewing plan"    resume     "$PLANNER_SESSION"  "02-plan-review.md"
}

stage_work() {
    run_step worker "Executing plan"     session-id "$WORKER_SESSION"   "03-worker-execute.md"
}

stage_review() {
    run_step planner "Reviewing work"        session-id "$PLANNER_SESSION"  "04-review-work.md"
    run_step planner "Creating follow-up"    resume     "$PLANNER_SESSION"  "05-followup-plan.md"
}

stage_followup() {
    run_step worker "Executing follow-up"    session-id "$WORKER_SESSION"   "06-worker-followup.md"
}

stage_report() {
    ((STEP++))
    log "Step $STEP: Copying original source into container ..."
    [[ -z "$REPO_DIR" ]] && die "No cached repo found for comparison."
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
