FROM ubuntu:24.04
ARG CLAUDE_VERSION=2.1.296
ENV DEBIAN_FRONTEND=noninteractive HOME=/root PATH=/root/.local/bin:$PATH
RUN apt-get update && apt-get install -y --no-install-recommends git python3 nodejs npm curl ca-certificates tmux \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_VERSION" && claude --version
COPY . /root/.claude/skills/weekly-roundup/
RUN rm -rf /root/.claude/skills/weekly-roundup/tests/out
WORKDIR /root
CMD ["sleep", "infinity"]
