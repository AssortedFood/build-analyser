#!/usr/bin/env bash
# lib/logging.sh — Logging via gum, agent helpers, banner

command -v gum > /dev/null 2>&1 || {
    echo "Error: gum is required but not installed." >&2
    echo "Install: https://github.com/charmbracelet/gum#installation" >&2
    exit 1
}

log()  { gum log --level info "$@"; }
ok()   { gum log --level info --prefix "  ok  " "$@"; }
warn() { gum log --level warn "$@"; }
err()  { gum log --level error "$@"; }
die()  { gum log --level fatal "$@"; exit 1; }

planner()  { gum log --level info --prefix "planner " "$@"; }
worker()   { gum log --level info --prefix "worker  " "$@"; }
reporter() { gum log --level info --prefix "reporter" "$@"; }

print_completion_banner() {
    echo ""
    gum style \
        --border double \
        --border-foreground 2 \
        --foreground 2 \
        --padding "0 2" \
        "Pipeline complete!" \
        "Output: $1"
}
