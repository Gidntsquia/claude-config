#!/bin/bash
# Sourced by win.sh / evshow.sh / screen-capture.sh / term-open.sh: resolves THIS session's state dir, so two evaluator
# sessions never see each other's windows, terminal or captures.
#   EVSHOW_STATE=<dir>            -> that dir (the eval harness sets it per run)
#   else $CLAUDE_CODE_SESSION_ID  -> ~/.claude/local-tools/evshow.state/<session id>  (a Claude Code session; the id is
#                                    the basename of its transcript ~/.claude/projects/<cwd slug>/<id>.jsonl)
#   else (plain shell)            -> the newest state dir whose transcript is in this cwd's project folder; if none,
#                                    a new one named after the newest .jsonl there (ev_state_dir create)
# Per-session files: launched.txt (window registry), term, history, log, queue, current, shown.png, gate.png, watcher pid,
# gate-capture loop pid, transcript (the one transcript the watcher follows).
EVROOT="$HOME/.claude/local-tools/evshow.state"
ev_transcripts_dir() { local slug; slug=$(pwd | tr '/' '-'); echo "${EVSHOW_TRANSCRIPTS:-$HOME/.claude/projects/$slug}"; }
ev_pick_transcript() {  # the transcript of this session: by id when known, else the newest .jsonl of this cwd
  local dir; dir=$(ev_transcripts_dir)
  if [ -z "${EVSHOW_TRANSCRIPTS:-}" ] && [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && [ -f "$dir/$CLAUDE_CODE_SESSION_ID.jsonl" ]; then
    echo "$dir/$CLAUDE_CODE_SESSION_ID.jsonl"; return 0; fi
  ls -t "$dir"/*.jsonl 2>/dev/null | head -1
}
ev_state_dir() {  # prints the session's state dir (may not exist yet); "create" makes it. Empty output = no session.
  local d dir t
  if [ -n "${EVSHOW_STATE:-}" ]; then d="$EVSHOW_STATE"
  elif [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then d="$EVROOT/$CLAUDE_CODE_SESSION_ID"
  else
    dir=$(ev_transcripts_dir)
    for d in $(ls -td "$EVROOT"/*/ 2>/dev/null); do
      t=$(cat "$d/transcript" 2>/dev/null); case "$t" in "$dir"/*) d="${d%/}"; break;; *) d="";; esac
    done
    if [ -z "$d" ]; then t=$(ev_pick_transcript); [ -n "$t" ] || return 1; t=$(basename "$t" .jsonl); d="$EVROOT/$t"; fi
  fi
  [ "${1:-}" = create ] && mkdir -p "$d"
  echo "$d"
}
ev_sid() { basename "$(ev_state_dir)"; }
ev_export() {  # env for winctl.ps1 / screen-capture.ps1 (powershell gets them through WSLENV)
  local d; d=$(ev_state_dir create) || return 1
  export EVSHOW_LAUNCHED="$(wslpath -w "$d/launched.txt")"
  export WSLENV="EVSHOW_LAUNCHED:EVSHOW_BEHIND:EVSHOW_TERMHWND${WSLENV:+:$WSLENV}"
}
