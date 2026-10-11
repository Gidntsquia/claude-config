#!/usr/bin/env bash
# Runs INSIDE a container. cc.sh <logfile> <prompt>: drives interactive claude (the Artifact tool is not
# available in headless `claude -p`) in a tmux session, waits for /tmp/cc.done, prints its content (a URL).
set -u
LOG="$1"; PROMPT="$2"; DONE=/tmp/cc.done
export IS_SANDBOX=1   # claude refuses --dangerously-skip-permissions as root without this
# The driving claude gets its own config dir so its sessions don't land in ~/.claude/projects (they would be
# counted as Misc by gather_data). Skills and state.json stay shared through a symlink.
export CLAUDE_CONFIG_DIR=/root/.claude-driver
mkdir -p "$CLAUDE_CONFIG_DIR"; ln -sfn /root/.claude/skills "$CLAUDE_CONFIG_DIR/skills"
cp /root/.claude/.credentials.json "$CLAUDE_CONFIG_DIR/.credentials.json"; chmod 600 "$CLAUDE_CONFIG_DIR/.credentials.json"
[ -f "$CLAUDE_CONFIG_DIR/.claude.json" ] || cp /root/.claude.json "$CLAUDE_CONFIG_DIR/.claude.json" 2>/dev/null
python3 - <<'EOF'
import json,os
p=os.environ["CLAUDE_CONFIG_DIR"]+"/.claude.json"; j=json.load(open(p)) if os.path.exists(p) else {}
j["bypassPermissionsModeAccepted"]=True; j["hasCompletedOnboarding"]=True
j.setdefault("projects",{}).setdefault("/root",{})["hasTrustDialogAccepted"]=True
json.dump(j,open(p,"w"))
EOF
rm -f "$DONE"; tmux kill-server 2>/dev/null; cd /root
tmux new-session -d -s cc -x 220 -y 60 "claude --dangerously-skip-permissions"   # must keep a TTY (no pipe)
tmux pipe-pane -t cc "cat >> '$LOG'"
for i in $(seq 1 60); do   # answer the trust / bypass dialogs ("Yes" is the 2nd option), wait for the input box
  pane=$(tmux capture-pane -p -t cc 2>/dev/null)
  if grep -q 'Yes, I accept\|Yes, I trust' <<<"$pane"; then tmux send-keys -t cc Down; sleep 0.5; tmux send-keys -t cc Enter; sleep 2; continue; fi
  grep -q '? for shortcuts\|❯ Try\|bypass permissions on' <<<"$pane" && break
  sleep 2
done
tmux send-keys -t cc -l "$PROMPT When completely finished, run in Bash: echo '<the URL asked for, or DONE>' > $DONE  (that file must be the very last thing you write)."
sleep 1; tmux send-keys -t cc Enter
for i in $(seq 1 400); do [ -s "$DONE" ] && break; sleep 3; done   # up to 20 min
sleep 2; tmux capture-pane -p -S -200 -t cc >> "$LOG" 2>/dev/null
tmux send-keys -t cc "/exit" Enter; sleep 3; tmux kill-server 2>/dev/null
[ -s "$DONE" ] && tr -d '\r' < "$DONE" | tail -1
