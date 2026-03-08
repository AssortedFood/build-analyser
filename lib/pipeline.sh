#!/usr/bin/env bash
# lib/pipeline.sh — Stage management and pipeline execution

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

# run_pipeline
# Uses globals: CURRENT_STAGE, STAGE_FILE, SCRIPT_DIR, PLANNER_SESSION,
#               WORKER_SESSION, REPORTER_SESSION, REPO_DIR, CONTAINER_NAME
run_pipeline() {
    # ── Stage: plan (steps 1+2) ──────────────────────────────────────────────
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

    # ── Stage: work (step 3) ─────────────────────────────────────────────────
    if [[ "$CURRENT_STAGE" == "planned" ]]; then
        worker "Step 3/9: Executing plan ..."
        run_claude --session-id "$WORKER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/03-worker-execute.md")"
        ok "Worker finished"

        echo "worked" > "$STAGE_FILE"
        CURRENT_STAGE="worked"
    fi

    # ── Stage: review (steps 4+5) ────────────────────────────────────────────
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

    # ── Stage: followup (step 6) ─────────────────────────────────────────────
    if [[ "$CURRENT_STAGE" == "reviewed" ]]; then
        worker "Step 6/9: Executing follow-up ..."
        run_claude --session-id "$WORKER_SESSION" -p "$(cat "$SCRIPT_DIR/prompts/06-worker-followup.md")"
        ok "Worker follow-up finished"

        echo "followed_up" > "$STAGE_FILE"
        CURRENT_STAGE="followed_up"
    fi

    # ── Stage: report (steps 7+8+9) ──────────────────────────────────────────
    if [[ "$CURRENT_STAGE" == "followed_up" ]]; then
        log "Step 7/9: Copying original source into container ..."
        [[ -z "$REPO_DIR" ]] && die "No cached repo found for comparison."
        docker cp "$REPO_DIR" "$CONTAINER_NAME:/home/claude/repo_build_files/original_src"
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
}
