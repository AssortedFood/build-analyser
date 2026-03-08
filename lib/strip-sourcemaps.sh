#!/usr/bin/env bash
# lib/strip-sourcemaps.sh — Remove all source map traces from a directory
#
# Usage: source lib/strip-sourcemaps.sh; strip_sourcemaps <directory>
#
# Handles three cases:
#   1. External .map files        → deleted
#   2. Inline source maps         → stripped from JS/CSS (base64 data URIs)
#   3. sourceMappingURL comments  → stripped from JS/CSS (file references)

strip_sourcemaps() {
    local dir="$1"
    local map_count=0 cleaned_count=0

    # 1. Delete external .map files
    while IFS= read -r -d '' f; do
        rm -f "$f"
        map_count=$((map_count + 1))
    done < <(find "$dir" -name '*.map' -type f -print0)

    # 2-3. Strip inline maps and sourceMappingURL comments from JS/CSS
    while IFS= read -r -d '' f; do
        if grep -qE '(//[#@]\s*sourceMappingURL=|/\*[#@]\s*sourceMappingURL=)' "$f" 2>/dev/null; then
            sed -i \
                -e 's|//[#@][[:space:]]*sourceMappingURL=.*$||' \
                -e 's|/\*[#@][[:space:]]*sourceMappingURL=.*\*/||' \
                "$f"
            cleaned_count=$((cleaned_count + 1))
        fi
    done < <(find "$dir" -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.css' \) -print0)

    log "Deleted $map_count .map file(s), cleaned $cleaned_count file(s)"
}
