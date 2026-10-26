#!/usr/bin/env bash
# usage: test/docker-install.sh
# Builds a fresh ubuntu:24.04 image with git, curl, python3, tmux and Claude Code (native installer), copies this
# clone in (tracked and untracked files, not git-ignored ones), and runs test/install-scenarios.sh --terminal as a
# normal user. Exits non-zero on any failure. Needs Docker.
set -eu
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG=claude-config-install-test
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT
mkdir -p "$CTX/clone"
( cd "$R" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
  | tar --null -T - -cf - ) | tar -xf - -C "$CTX/clone"
cat > "$CTX/Dockerfile" <<'DOCKER'
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git curl ca-certificates python3 tmux bash && rm -rf /var/lib/apt/lists/*
RUN useradd -m -d /tester -s /bin/bash tester
USER tester
WORKDIR /tester
RUN curl -fsSL https://claude.ai/install.sh | bash
COPY --chown=tester:tester clone /tester/claude-config
ENV PATH=/tester/.local/bin:$PATH
DOCKER
docker build -q -t "$IMG" "$CTX" >/dev/null
docker run --rm "$IMG" bash -lc 'cd ~/claude-config && git init -q 2>/dev/null; bash test/install-scenarios.sh --terminal'
