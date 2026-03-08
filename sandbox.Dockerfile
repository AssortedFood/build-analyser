# ─────────────────────────────────────────────────────────────────────────────
# claude-sandbox-builder
# ─────────────────────────────────────────────────────────────────────────────

FROM debian:bookworm-slim

ARG NODE_VERSION=20
ARG WORKDIR=/home/claude/repo_build_files

ENV DEBIAN_FRONTEND=noninteractive

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    bash curl wget git jq tree unzip zip tar \
    openssh-client ca-certificates gnupg sudo \
    build-essential procps findutils diffutils \
    ripgrep fd-find bat less vim nano \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js ──────────────────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Claude Code CLI ──────────────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code

# ── Workspace setup ──────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash -u 1000 claude \
    && mkdir -p ${WORKDIR} \
    && chown -R claude:claude ${WORKDIR}

WORKDIR ${WORKDIR}

# ── Copy build artifacts ─────────────────────────────────────────────────────
COPY --chown=claude:claude build-output/ ${WORKDIR}/build/
COPY --chown=claude:claude CLAUDE.m[d] ${WORKDIR}/
COPY --chown=claude:claude package.json ${WORKDIR}/package.json

# ── Empty src and docs directories ───────────────────────────────────────────
RUN mkdir -p ${WORKDIR}/src ${WORKDIR}/docs && chown claude:claude ${WORKDIR}/src ${WORKDIR}/docs

# ── Prompt files ─────────────────────────────────────────────────────────────
COPY --chown=claude:claude prompts/ ${WORKDIR}/prompts/

# ── Environment ──────────────────────────────────────────────────────────────
ENV LANG=C.UTF-8
ENV TERM=xterm-256color

USER claude

CMD ["bash"]
