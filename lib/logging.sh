#!/usr/bin/env bash
# lib/logging.sh — Colors, log functions, agent helpers, banner

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

planner() { echo -e "${CYAN}[planner]${NC} $*"; }
worker()  { echo -e "${CYAN}[worker ]${NC} $*"; }
reporter(){ echo -e "${CYAN}[reporter]${NC} $*"; }

print_completion_banner() {
    local output_dir="$1"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Pipeline complete!${NC}"
    echo -e "${GREEN}  Output: $output_dir${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
