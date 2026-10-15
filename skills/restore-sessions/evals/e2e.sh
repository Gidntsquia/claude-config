#!/usr/bin/env bash
# End-to-end test of /restore-sessions' scripts on a PRIVATE tmux server (tmux -L rs-e2e); the user's tmux is never
# touched. Uses four real throwaway Claude sessions (haiku, one-word replies) so `claude --resume` really runs.
#   e2e.sh prep DIR   create the four sessions in DIR/{alpha,beta,gamma,delta} and accept folder trust for each
#                     (costs four tiny haiku calls; trust is accepted in a separate private server rs-e2e-prep)
#   e2e.sh run DIR    copy their transcripts into DIR/projects with mtimes as if a stop hit at 2026-10-15 04:56:11 ET,
#                     build session 0 like tmux-quad (4 panes) with delta already resumed in pane 2, then run
#                     find-sessions -> plan (with and without "drop beta") -> apply -> verify and check R5, R6, R8,
#                     R9, R10, R13. Session 1 does not exist, so a Windows Terminal window opens attached to it.
#   e2e.sh skill DIR  same setup, then start an interactive claude (private server rs-e2e-drv) with RS_TMUX_L=rs-e2e and
#                     RS_PROJECTS=DIR/projects and type "/restore-sessions 2026-10-15 04:56:11" into it; answer it by hand
#   e2e.sh clean DIR  close that Windows Terminal window and end the private test server (never the user's).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; S="$here/../scripts"
cmd="${1:-}"; W="${2:-}"; [ -n "$cmd" ] && [ -n "$W" ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
mkdir -p "$W"; W="$(realpath "$W")"
SOCK=rs-e2e; T() { tmux -L "$SOCK" "$@"; }
end_server() {  # ends a PRIVATE test server by its pid (only rs-e2e*, never the default server)
  case "$1" in rs-e2e*) ;; *) echo "refusing to end tmux server $1"; return 1 ;; esac
  local pid; pid=$(tmux -L "$1" display -p '#{pid}' 2>/dev/null) && [ -n "$pid" ] && kill "$pid" && echo "ended test server $1 (pid $pid)"
}
pass=0 fail=0
check() { if [ "$1" = 0 ]; then echo "PASS $2"; pass=$((pass+1)); else echo "FAIL $2"; fail=$((fail+1)); fi; }

case "$cmd" in
prep)
  : > "$W/ids.tsv"
  for spec in alpha:worker beta: gamma:planner delta:worker; do
    n=${spec%%:*} a=${spec#*:}; mkdir -p "$W/$n"
    id=$(cd "$W/$n" && claude -p --model haiku ${a:+--agent "$a"} --output-format json "Reply with exactly: ok" | jq -r .session_id)
    printf '%s\t%s\t%s\n' "$n" "$id" "$a" >> "$W/ids.tsv"; echo "$n $id agent=${a:-none}"
  done
  P=rs-e2e-prep; tmux -L $P new-session -d -s t -x 200 -y 50
  for n in alpha beta gamma delta; do
    tmux -L $P send-keys -t t "cd '$W/$n' && claude" Enter; sleep 8
    if tmux -L $P capture-pane -p -t t | grep -q 'trust this folder'; then tmux -L $P send-keys -t t Down Enter; sleep 6; fi
    tmux -L $P send-keys -t t C-c; sleep 0.3; tmux -L $P send-keys -t t C-c; sleep 2
    echo "$n: trusted; pane back at $(tmux -L $P display -p -t t '#{pane_current_command}')"
  done
  end_server $P ;;
run|skill)
  [ -s "$W/ids.tsv" ] || { echo "run 'e2e.sh prep $W' first"; exit 2; }
  id() { awk -v n="$1" '$1 == n { print $2 }' "$W/ids.tsv"; }
  rm -rf "$W/projects" "$W/out"; mkdir -p "$W/projects" "$W/out"
  sec=1
  for n in alpha beta gamma delta; do
    src=$(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name "$(id $n).jsonl" | head -1)
    d="$W/projects/$(basename "$(dirname "$src")")"; mkdir -p "$d"; cp "$src" "$d/"
    touch -d "2026-10-15T04:56:0${sec}-04:00" "$d/$(id $n).jsonl"; sec=$((sec+1))
  done
  T has-session -t 0 2>/dev/null && { echo "test server $SOCK already has session 0: run 'e2e.sh clean $W' first"; exit 2; }
  T new-session -d -s 0 -c "$HOME" -x 200 -y 50
  for _ in 1 2 3; do T split-window -d -t 0:1 -c "$HOME"; done; T select-layout -t 0:1 tiled
  T send-keys -t 0:1.2 "cd '$W/delta' && claude --resume $(id delta)" Enter
  sleep 12
  T list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id}' > "$W/out/before-ids.txt"
  echo "== before"; T list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'

  if [ "$cmd" = skill ]; then
    # Drive the real skill: an interactive claude on a second private server, its scripts pointed at rs-e2e.
    D=rs-e2e-drv; tmux -L $D has-session -t d 2>/dev/null && { echo "$D already running: clean first"; exit 2; }
    tmux -L $D new-session -d -s d -x 220 -y 60 -c "$W/alpha" \
      "env RS_TMUX_L=$SOCK RS_PROJECTS='$W/projects' claude --model sonnet; exec bash"
    sleep 8; tmux -L $D send-keys -t d "/restore-sessions 2026-10-15 04:56:11"; sleep 1; tmux -L $D send-keys -t d Enter
    echo "driver: tmux -L $D attach -t d   (answer the question there, or with send-keys)"; exit 0
  fi
  echo "== find-sessions"
  "$S/find-sessions.sh" '2026-10-15 04:56:11' "$W/projects" | tee "$W/out/candidates.tsv" | cut -f1-7
  export RS_TMUX_L=$SOCK
  echo "== plan with: drop $(id beta | cut -c1-8)"
  "$S/plan.sh" --candidates "$W/out/candidates.tsv" --out "$W/out/dropped" --fix "drop $(id beta | cut -c1-8)" | tee "$W/out/plan-dropped.md"
  ! grep -q "| $(id beta) |" "$W/out/plan-dropped.md" && grep -q "$(id beta | cut -c1-8) .*dropped by user" "$W/out/plan-dropped.md"
  check $? "R7: 'drop <id>' removes that row and lists it as dropped by user"
  echo "== plan (accepted as proposed)"
  "$S/plan.sh" --candidates "$W/out/candidates.tsv" --out "$W/out" | tee "$W/out/plan.md"
  grep -q "$(id delta | cut -c1-8) .*already running" "$W/out/plan.md"; check $? "R5: delta listed as already running"
  echo "== apply"; "$S/apply.sh" "$W/out"
  echo "== verify"; "$S/verify.sh" "$W/out" | tee "$W/out/report.md"

  echo "== checks"
  dpane=$(awk '$1 == "0:1.2" { print $2 }' "$W/out/before-ids.txt")
  ! grep -q "send-keys -t $dpane " "$W/out/actions.log"; check $? "R5: nothing sent to the pane already running delta ($dpane)"
  missing=0; while read -r _ pid; do T display -p -t "$pid" '#{pane_id}' >/dev/null 2>&1 || missing=1; done < "$W/out/before-ids.txt"
  check $missing "R5: every pre-existing pane still present"
  echo "list-panes -t 0:"; T list-panes -t '=0:' -F '#{pane_index} #{pane_current_command}' | tee "$W/out/s0.txt"
  [ "$(tr '\n' ' ' < "$W/out/s0.txt")" = "1 terminal-pet 2 claude 3 claude 4 claude " ]
  check $? "R6: session 0 pane 1 terminal-pet, panes 2-4 claude"
  echo "list-panes -t 1:"; T list-panes -t '=1:' -F '#{pane_index} #{pane_current_command}'
  pets=$(for p in $(T list-panes -a -F '#{pane_pid}'); do ps -o args= --ppid "$p"; done | grep '^terminal-pet' | sed 's/^terminal-pet$/terminal-pet (squid)/')
  echo "$pets"; [ "$(echo "$pets" | wc -l)" = 2 ] && [ "$(echo "$pets" | sort -u | wc -l)" = 2 ]
  check $? "R8: two windows, two different pets"
  for n in alpha beta gamma; do
    p=$(awk -F'\t' -v i="$(id $n)" '$5 == i { print $4 }' "$W/out/plan.tsv"); pid=$(awk -v k="$p" '$1 == k { print $2 }' "$W/out/panes-final.tsv")
    sh=$(T capture-pane -a -p -J -t "$pid")
    grep -qF "claude --resume $(id $n)" <<<"$sh" || sh=$(cat "$W/out/sent-${pid#%}.txt")   # cut by a resize: use apply's copy
    c=$(T capture-pane -p -J -t "$pid" | sed 's/\xc2\xa0/ /g')   # Claude pads its prompt with no-break spaces
    echo "$n shell screen (capture-pane -a):"; grep -v '^$' <<<"$sh" | sed 's/^/    /'
    [ "$(grep -c "claude --resume" <<<"$sh")" = 1 ] && grep -v '^ *$' <<<"$sh" | tail -1 | grep -qF "cd '$W/$n' && claude --resume $(id $n)" && grep -qx '❯ *' <<<"$c"
    check $? "R9: $n pane shows the one resume line and an empty Claude prompt"
  done
  [ "$(grep -c 'send-keys' "$W/out/actions.log")" = 5 ]; check $? "R9: exactly 5 send-keys (2 pets + 3 resumes)"
  grep -Eq "frontmost|in the taskbar" "$W/out/wt.tsv" && [ -n "$(T list-clients -t 1)" ]
  check $? "R10: Windows Terminal window attached to new session 1 ($(cut -f4 "$W/out/wt.tsv"))"
  k=kill; ! grep -rnE "$k-server|$k-session|$k-pane|$k-window" "$here/.." ; check $? "R13: no tmux kill commands in the skill dir"
  echo "passed $pass, failed $fail"; [ "$fail" = 0 ] ;;
clean)
  h=$(cut -f3 "$W/out/wt.tsv" 2>/dev/null | head -1)
  for f in "$HOME"/.cache/restore-sessions/*/wt.tsv; do   # windows the driven skill opened on the test server
    [ -f "$f" ] && grep -q "$SOCK" "$(dirname "$f")/actions.log" 2>/dev/null && h="$h $(cut -f3 "$f")"
  done
  end_server $SOCK; tmux -L rs-e2e-drv has-session 2>/dev/null && end_server rs-e2e-drv
  sleep 2
  for x in $h; do "$HOME/.claude/local-tools/win.sh" reg "$x" "tmux 1 (restored)" >/dev/null 2>&1   # it may have been opened by the driven skill's session
    "$HOME/.claude/local-tools/win.sh" close "$x" >/dev/null 2>&1 && echo "closed window $x" || echo "window $x already closed"; done ;;
*) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
