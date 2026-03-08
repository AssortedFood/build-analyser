#!/usr/bin/env bash
# lib/detect.sh — Package manager, build command, and output directory detection

# detect_package_manager <repo-dir>
# Sets: PM, PM_INSTALL
detect_package_manager() {
    local dir="$1"

    if [[ -f "$dir/pnpm-lock.yaml" ]]; then
        PM="pnpm"
        PM_INSTALL="pnpm install --frozen-lockfile"
    elif [[ -f "$dir/yarn.lock" ]]; then
        PM="yarn"
        PM_INSTALL="yarn install --frozen-lockfile"
    elif [[ -f "$dir/bun.lockb" ]] || [[ -f "$dir/bun.lock" ]]; then
        PM="bun"
        PM_INSTALL="bun install"
    else
        PM="npm"
        PM_INSTALL="npm ci --ignore-scripts=false 2>/dev/null || npm install"
    fi

    log "Detected package manager: $PM"
}

# detect_build_cmd <repo-dir>
# Sets: BUILD_CMD
detect_build_cmd() {
    local dir="$1"
    BUILD_CMD=""

    # 1. Check package.json scripts
    if [[ -f "$dir/package.json" ]]; then
        for script in build compile dist generate; do
            if jq -e ".scripts.\"$script\"" "$dir/package.json" > /dev/null 2>&1; then
                BUILD_CMD="$PM run $script"
                return
            fi
        done
    fi

    # 2. Infer from framework config files (checked in priority order)
    local frameworks=(
        "next.config.*"    "npx next build"
        "nuxt.config.*"    "npx nuxt build"
        "astro.config.*"   "npx astro build"
        "svelte.config.*"  "npx svelte-kit sync && npx vite build"
        "angular.json"     "npx ng build"
        "vite.config.*"    "npx vite build"
        "webpack.config.*" "npx webpack --mode production"
        "rollup.config.*"  "npx rollup -c"
        "tsconfig.json"    "npx tsc"
    )

    local i
    for (( i=0; i<${#frameworks[@]}; i+=2 )); do
        if compgen -G "$dir/${frameworks[$i]}" > /dev/null; then
            BUILD_CMD="${frameworks[$i+1]}"
            warn "No build script in package.json — inferred from ${frameworks[$i]}"
            return
        fi
    done

    die "No build script found in package.json (tried: build, compile, dist, generate) and no framework config detected"
}

# detect_build_output <repo-dir>
# Sets: BUILD_DIR
detect_build_output() {
    local dir="$1"
    BUILD_DIR=""

    for candidate in dist build out .next .output output public/build; do
        if [[ -d "$dir/$candidate" ]]; then
            BUILD_DIR="$candidate"
            return
        fi
    done

    die "Could not auto-detect build directory."
}
