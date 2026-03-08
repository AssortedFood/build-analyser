#!/usr/bin/env bash
# lib/logging.sh — Logging via gum, agent helpers, banner

command -v gum > /dev/null 2>&1 || {
    echo "Error: gum is required but not installed." >&2
    echo "Install: https://github.com/charmbracelet/gum#installation" >&2
    exit 1
}

# ── Timestamp style ───────────────────────────────────────────────────────────
# Time-only (HH:MM:SS) with a dark background badge and padding.
TS_FMT=" 15:04:05 "
TS_BG=236
TS_FG=252

_gum_log() { gum log --time "$TS_FMT" --time.background "$TS_BG" --time.foreground "$TS_FG" "$@"; }

# ── General logging ───────────────────────────────────────────────────────────

log()  { _gum_log --level info "$@"; }
ok()   { _gum_log --level info --prefix "✓" --prefix.foreground 2 "$@"; }
warn() { _gum_log --level warn "$@"; }
err()  { _gum_log --level error "$@"; }
die()  { _gum_log --level fatal "$@"; exit 1; }

# ── Agent logging (distinct colors) ──────────────────────────────────────────
#   planner  = cyan (39)     — thinking, planning
#   worker   = yellow (214)  — executing
#   reporter = magenta (170) — analysing, reporting

planner()  { _gum_log --level info --prefix "planner " --prefix.foreground 39  "$@"; }
worker()   { _gum_log --level info --prefix "worker  " --prefix.foreground 214 "$@"; }
reporter() { _gum_log --level info --prefix "reporter" --prefix.foreground 170 "$@"; }

# ── Agent colors ──────────────────────────────────────────────────────────────

agent_color() {
    case "$1" in
        planner)  echo 39  ;;
        worker)   echo 214 ;;
        reporter) echo 170 ;;
        *)        echo 7   ;;
    esac
}

# ── Step header ───────────────────────────────────────────────────────────────

step_header() {
    local color="$1" label="$2"
    echo ""
    gum style \
        --foreground "$color" \
        --bold \
        --border-foreground "$color" \
        --border rounded \
        --padding "0 1" \
        "$label"
}

# ── LLM output stream ────────────────────────────────────────────────────────
# Prepends a timestamp badge to the first line of each new LLM message.
# New messages are delimited by a zero-width space line (U+200B) emitted
# by the jq filter in run_claude.

ts_badge() {
    printf '\033[48;5;%dm\033[38;5;%dm %s \033[0m' "$TS_BG" "$TS_FG" "$(date +%H:%M:%S)"
}

# stamp_stream
# Reads streaming LLM output, detects message boundaries via U+200B markers,
# and prepends a timestamp badge to the first line of each message.
stamp_stream() {
    local new_msg=false
    local zwsp=$'\xe2\x80\x8b'  # UTF-8 for U+200B

    while IFS= read -r line; do
        if [[ "$line" == "$zwsp" ]]; then
            new_msg=true
            echo ""
        elif [[ "$new_msg" == true ]] && [[ -z "$line" ]]; then
            continue
        elif [[ "$new_msg" == true ]]; then
            printf '%s %s\n' "$(ts_badge)" "$line"
            new_msg=false
        else
            echo "$line"
        fi
    done
}

# ── Completion banner ─────────────────────────────────────────────────────────

print_completion_banner() {
    echo ""
    gum style \
        --border double \
        --border-foreground 2 \
        --foreground 2 \
        --bold \
        --padding "0 2" \
        "Pipeline complete!" \
        "Output: $1"
}
