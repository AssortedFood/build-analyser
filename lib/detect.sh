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
    local configs=(
        "next.config.js"    "npx next build"
        "next.config.ts"    "npx next build"
        "next.config.mjs"   "npx next build"
        "nuxt.config.js"    "npx nuxt build"
        "nuxt.config.ts"    "npx nuxt build"
        "nuxt.config.mjs"   "npx nuxt build"
        "astro.config.js"   "npx astro build"
        "astro.config.ts"   "npx astro build"
        "astro.config.mjs"  "npx astro build"
        "svelte.config.js"  "npx svelte-kit sync && npx vite build"
        "angular.json"      "npx ng build"
        "vite.config.js"    "npx vite build"
        "vite.config.ts"    "npx vite build"
        "vite.config.mjs"   "npx vite build"
        "webpack.config.js" "npx webpack --mode production"
        "webpack.config.ts" "npx webpack --mode production"
        "rollup.config.js"  "npx rollup -c"
        "rollup.config.ts"  "npx rollup -c"
        "rollup.config.mjs" "npx rollup -c"
        "tsconfig.json"     "npx tsc"
    )

    local i
    for (( i=0; i<${#configs[@]}; i+=2 )); do
        if [[ -f "$dir/${configs[$i]}" ]]; then
            BUILD_CMD="${configs[$i+1]}"
            warn "No build script in package.json — inferred from ${configs[$i]}"
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
