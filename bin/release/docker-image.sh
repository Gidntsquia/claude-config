#!/usr/bin/env bash
# usage: bin/release/docker-image.sh [--build-only]
# Builds a fresh ubuntu:24.04 image with git, curl, python3, tmux and Claude Code (native installer), copies this
# clone in (its git history and tags, plus the tracked and untracked files as they are now, not git-ignored ones),
# and runs the install tests (test/quick/install-*.bats) as a normal user. Exits non-zero on any failure. Needs Docker.
# The history is there because the oldtag, plist and dirty scenarios install from older commits; SCN_NEED_OLDTAG=1
# makes a clone without them a failure. --build-only stops after the build and prints the image name
# (bin/release/rehearsal.sh uses it).
set -eu
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMG=claude-config-install-test
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT
if git -C "$R" rev-parse --git-dir >/dev/null 2>&1; then
  git clone -q "$R" "$CTX/clone"
  git -C "$CTX/clone" checkout -q "$(git -C "$R" rev-parse HEAD)"
  ( cd "$R" && git diff -z --name-only --no-renames --diff-filter=D HEAD ) | ( cd "$CTX/clone" && xargs -0 rm -f -- )
else
  mkdir -p "$CTX/clone"
fi
( cd "$R" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
  | tar --null -T - -cf - ) | tar -xf - -C "$CTX/clone"
cat > "$CTX/Dockerfile" <<'DOCKER'
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git curl ca-certificates python3 tmux bash bats && rm -rf /var/lib/apt/lists/*
RUN useradd -m -d /tester -s /bin/bash tester
USER tester
WORKDIR /tester
RUN curl -fsSL https://claude.ai/install.sh | bash
COPY --chown=tester:tester clone /tester/claude-config
ENV PATH=/tester/.local/bin:$PATH
DOCKER
docker build -q -t "$IMG" "$CTX" >/dev/null
if [ "${1:-}" = --build-only ]; then echo "$IMG"; exit 0; fi
docker run --rm -e SCN_NEED_OLDTAG="${SCN_NEED_OLDTAG:-}" "$IMG" \
  bash -lc 'cd ~/claude-config && { [ -d .git ] || git init -q; } && bats --tap test/quick/install-*.bats'
