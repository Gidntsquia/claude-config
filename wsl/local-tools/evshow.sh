#!/bin/bash
# Shows evaluator items the instant the user's AskUserQuestion answer lands, without waiting for the model's next command.
# It watches THIS session's transcript (~/.claude/projects/<cwd slug>/<session id>.jsonl). ALL items are opened HIDDEN
# (win-app.sh --hidden / term-open.sh: hooked at creation, off-screen + alpha 0, no taskbar button) before
# arming; nothing is launched after the readiness answer.
#   evshow.sh arm first "<title1>" ["<title2>" ...]   -> before the readiness question. Queue of every item's unique title,
#        in asking order, all already opened hidden. Starts the watcher and a gate-capture loop (captures the screen every
#        ~2.5 s while the question is open). On the answer "Yes": fginfo + place terminal 0 0 1020 1400 + show "<title1>"
#        1030 0 1530 1400 + capture, in ONE PowerShell process; picks the last gate capture finished while the question was open.
#   evshow.sh wait [timeout-s]        -> the FIRST command after every answer. Blocks until the show (and its capture) is done,
#        prints the log: answer time, shown:, elapsed s, capture path; copies the capture to <state>/shown.png (and the
#        gate capture to <state>/gate.png after the readiness answer). Then it auto-arms the NEXT title of the queue
#        (on that answer: untop+close the current item, show the next, capture). If the watcher did not fire within 1.5 s it
#        fires the show itself. Exit 1 on "not shown". Ask the item question right after `shown:`; read the captures only
#        on `not shown` or an answer other than Works.
#   evshow.sh arm next <oldHWND> "<title>"  -> manual re-arm (e.g. after a reopen with a fresh title); 0 = nothing to close.
#   evshow.sh end                     -> after the last answer: untop+close the current item, restore the terminal with the
#        saved fginfo line (prints the `now` line), disarm, list-topmost.
#   evshow.sh path shown|gate|zlog|dir -> this session's shown.png / gate.png / zlog (100 ms z-order samples) / state dir path
#   evshow.sh noflash                 -> "no-flash: PASS (...)" or "no-flash: FAIL (...)": no run window un-cloaked and on-screen in
#        the zlog before its own show-start, every hidden: line's exposure (hidden-ms - visible-ms) <= 16 (exit 1 on FAIL); quote it in EVAL.md
#   evshow.sh disarm | status | history
# State is PER SESSION: ~/.claude/local-tools/evshow.state/<session id>/ (EVSHOW_STATE=<dir> overrides; see evsession.sh).
# wait / next / end act only on windows in that session's launched.txt and restore only that session's terminal;
# with nothing armed for this session they print `no session` and exit 1.
# Geometry: terminal 0 0 1020 1400, item 1030 0 1530 1400 (EVSHOW_TERM="X Y W H" EVSHOW_ITEM="X Y W H" override);
# EVSHOW_TRANSCRIPTS=<dir> takes the newest *.jsonl there as the transcript (eval harness); EVSHOW_BEHIND=1 = windows
# go to the very bottom of the z-order (see win.sh). EVSHOW_TERMHWND=<HWND> uses that window as the terminal (tests).
grep -qi microsoft /proc/version 2>/dev/null || { echo "evshow.sh: WSL only (this is $(uname))" >&2; exit 1; }
set -u
. "$HOME/.claude/local-tools/evsession.sh"
. "$HOME/.claude/local-tools/winenv.sh"
W="$HOME/.claude/local-tools/win.sh"
PY="$HOME/.claude/local-tools/evshow_watch.py"
CAP="$HOME/.claude/local-tools/screen-capture.sh"
et() { TZ=America/New_York date +%T.%N | cut -c1-12; }
secs() { python3 -I -c "
import sys,datetime as d
f=lambda s:d.datetime.strptime(s[:12],'%H:%M:%S.%f')
a,b=f(sys.argv[1]),f(sys.argv[2]); print(round((b-a).total_seconds(),2))" "$1" "$2"; }
TERMG=${EVSHOW_TERM:-"0 0 1020 1400"}; ITEMG=${EVSHOW_ITEM:-"1030 0 1530 1400"}
hist() { local x; for x in "$@"; do [ -n "$x" ] && printf '%s\n' "$x" | tee -a "$D/history" >> "$D/log"; done; }
need_session() {  # wait/next/end/fired/gateloop: something must be armed for this session
  if [ -z "$D" ] || [ ! -e "$D/mode" ]; then echo "no session: nothing armed for this session (state dir ${D:-none}); run evshow.sh arm first ... first"; exit 1; fi; }

pick_gate() {  # the last gate capture finished before the answer; says whether the question was already on screen
  local ans ask best="" bestt="" t p
  ans=$(cat "$D/answer" 2>/dev/null); ask=$(cat "$D/question-ts" 2>/dev/null)
  [ -s "$D/gates" ] || { hist "gate-capture: none taken"; return; }
  while read -r t p; do [ "$t" \< "$ans" ] && { best=$p; bestt=$t; }; done < "$D/gates"
  [ -n "$best" ] || { hist "gate-capture: none finished before the answer"; return; }
  cp "$best" "$D/gate.png" 2>/dev/null; echo "$D/gate.png" > "$D/gate-capture"
  if [ -n "$ask" ] && [ "$bestt" \> "$ask" ]; then
    hist "gate-capture $D/gate.png (finished $bestt ET, question emitted $ask, answered $ans: taken while the question was open)"
  else
    hist "gate-capture $D/gate.png (finished $bestt ET, question emitted ${ask:-?}, answered $ans: finished BEFORE the question appeared; the question was open for less than one capture period)"
  fi; }

fire() {  # runs the armed show once (lock), logs, marks $D/done. $1 = who fired, $2 = answer time (ET) or ""
  exec 9>"$D/lock"; flock -n 9 || { exec 9>&-; return 0; }
  [ -e "$D/done" ] && { exec 9>&-; return 0; }
  local mode title old out rc t0 t1 capw capl
  mode=$(cat "$D/mode"); title=$(cat "$D/title"); old=$(cat "$D/old" 2>/dev/null || echo 0)
  if [ -e "$D/gatepid" ]; then kill -- -"$(cat "$D/gatepid")" 2>/dev/null; pkill -P "$(cat "$D/gatepid")" 2>/dev/null; rm -f "$D/gatepid"; fi
  capl="$WIN_HOME/evshow-shown-$SID8-$(date +%s).png"; capw="$WIN_HOME_W\\$(basename "$capl")"
  t0=$(et); read -r ix iy iw ih <<<"$ITEMG"; read -r tx ty tw th <<<"$TERMG"
  if [ "$mode" = first ]; then
    local me; me=$(cut -d' ' -f1 "$D/term" 2>/dev/null)   # the terminal `win.sh me` found; else whatever is foreground
    out=$("$W" start "$title" "$ix" "$iy" "$iw" "$ih" 5 "$tx" "$ty" "$tw" "$th" "${EVSHOW_TERMHWND:-$me}" "$capw"); rc=$?
    local fg; fg=$(printf '%s\n' "$out" | grep '^fginfo ' | cut -d' ' -f2-); [ -n "$fg" ] && echo "$fg" > "$D/term"
  else
    local term; term=$(cut -d' ' -f1 "$D/term" 2>/dev/null)
    out=$("$W" next "$old" "$title" "$ix" "$iy" "$iw" "$ih" 5 "$term" "$capw"); rc=$?
  fi
  local tdone; tdone=$(et); t1=""
  # shown-at = when the capture file was created (the capture starts right after the show checks pass); else process end
  if printf '%s\n' "$out" | grep -q '^shown: ' && [ -f "$capl" ]; then t1=$(TZ=America/New_York stat -c %y "$capl" | cut -d' ' -f2 | cut -c1-12); fi
  [ -n "$t1" ] || t1=$tdone
  hist "fired-by $1" "${2:+answer $2 (transcript timestamp, ET)}" "show-start $t0" "shown-at $t1 (process done $tdone)"
  [ -n "$2" ] && hist "elapsed $(secs "$2" "$t1") s (answer -> shown)"
  hist "$out" "rc $rc"
  [ "$rc" -ne 0 ] && hist "$("$W" close-cloaked 2>&1)"   # not shown: the cloaked window of this attempt is closed, never left behind
  if printf '%s\n' "$out" | grep -q '^shown: '; then
    printf '%s\n' "$out" | grep '^shown: ' | cut -d' ' -f2 > "$D/current"; echo "$t1" > "$D/last-shown"
    [ -f "$capl" ] && { cp "$capl" "$D/shown.png"; hist "capture $D/shown.png (copy of $capl, taken after shown)"; }
  fi
  [ "$mode" = first ] && pick_gate
  echo "$rc" > "$D/done"; exec 9>&-
}

arm() {  # arm first|next <title> <oldHWND>; sets per-item state and starts the watcher on this session's transcript
  local mode=$1 title=$2 old=$3
  "$0" disarm >/dev/null 2>&1
  rm -f "$D"/{log,done,lock,mode,title,old,answer,pid,question-ts,gates,gatepid}
  if [ "$mode" = first ] || [ ! -s "$D/transcript" ]; then
    local tr; tr=$(ev_pick_transcript); [ -n "$tr" ] || { echo "no transcript found in $(ev_transcripts_dir)"; exit 1; }
    echo "$tr" > "$D/transcript"
  fi
  echo "$mode" > "$D/mode"; printf '%s' "$title" > "$D/title"; echo "$old" > "$D/old"
  echo "$(et) armed $mode '$title'" > "$D/log"; echo "$(et) armed $mode '$title'" >> "$D/history"
  nohup python3 -I "$PY" "$(cat "$D/transcript")" "$mode" "$title" "$D" >> "$D/watch.err" 2>&1 &
  echo $! > "$D/pid"
  if [ "$mode" = first ]; then setsid "$0" gateloop >/dev/null 2>&1 & echo $! > "$D/gatepid"
    setsid "$W" zlog 1800 > "$D/zlog" 2>/dev/null & echo $! > "$D/zpid"; fi   # 100 ms z-order sampler until `end`
  echo "armed $mode '$title' (watcher pid $(cat "$D/pid"), transcript $(cat "$D/transcript"), state $D)"
}

case "${1:-}" in
  arm)
    D=$(ev_state_dir create) || { echo "no session: no transcript for this cwd (set EVSHOW_STATE or run inside a Claude Code session)"; exit 1; }
    export EVSHOW_STATE="$D"; SID8=$(basename "$D" | cut -c1-8)
    shift; mode=${1:-}; shift
    case "$mode" in
      first) [ $# -ge 1 ] || { echo "usage: arm first \"<title1>\" [\"<title2>\" ...]"; exit 1; }
        rm -f "$D"/{history,queue,idx,current,last-shown,gate.png,shown.png,gate-capture,transcript,zlog,zpid}   # term (win.sh me) is kept
        printf '%s\n' "$@" > "$D/queue"; echo 1 > "$D/idx"; echo "queue: $# item(s) (session $(basename "$D"))"; arm first "$1" 0;;
      next) [ $# -ge 2 ] || { echo "usage: arm next <oldHWND> \"<title>\""; exit 1; }; [ -e "$D/queue" ] || { echo "no session: nothing armed for this session ($D)"; exit 1; }; arm next "$2" "$1";;
      *) echo "usage: arm first|next ..."; exit 1;;
    esac;;
  path)
    D=$(ev_state_dir) || { echo "no session"; exit 1; }
    case "${2:-}" in shown) echo "$D/shown.png";; gate) echo "$D/gate.png";; zlog) echo "$D/zlog";; dir|"") echo "$D";; *) echo "usage: path shown|gate|zlog|dir"; exit 1;; esac;;
  noflash) D=$(ev_state_dir) || { echo "no session"; exit 1; }; python3 -I "$HOME/.claude/local-tools/evshow_noflash.py" "$D";;
  gateloop)  # captures the screen every ~2.5 s until the answer; rotates 4 files; records finish time (ET) + path
    D=$(ev_state_dir); export EVSHOW_STATE="$D"; SID8=$(basename "$D" | cut -c1-8)
    i=0; while [ ! -e "$D/answer" ] && [ ! -e "$D/done" ]; do
      p=$("$CAP" "evshow-gate-$SID8-$((i % 4))") || { sleep 1; continue; }
      echo "$(et) $p" >> "$D/gates"; i=$((i+1)); sleep 1
    done;;
  fired) D=$(ev_state_dir); export EVSHOW_STATE="$D"; SID8=$(basename "$D" | cut -c1-8); need_session; fire watcher "${2:-}";;      # called by the watcher
  wait)
    D=$(ev_state_dir) || D=""; need_session; export EVSHOW_STATE="$D"; SID8=$(basename "$D" | cut -c1-8)
    to=${2:-8}; t=$(et); n=0
    while [ ! -e "$D/done" ] && [ $n -lt $((to*10)) ]; do
      sleep 0.1; n=$((n+1))
      if [ $n -ge 15 ] && [ ! -e "$D/done" ]; then fire "wait-fallback (watcher did not fire by $t)" "$(cat "$D/answer" 2>/dev/null)"; fi
    done
    echo "wait-called $t (session $(basename "$D"))"; cat "$D/log" 2>/dev/null
    [ -e "$D/done" ] || { echo "not shown: nothing fired within ${to}s"; exit 1; }
    rc=$(cat "$D/done")
    if grep -q '^shown: ' "$D/log"; then
      cur=$(cat "$D/current"); idx=$(cat "$D/idx" 2>/dev/null || echo 0); n=$(wc -l < "$D/queue" 2>/dev/null || echo 0)
      [ -s "$D/term" ] && echo "terminal (saved fginfo): $(cat "$D/term")"
      if [ "$idx" -gt 0 ] && [ "$idx" -lt "$n" ]; then
        nxt=$(sed -n "$((idx+1))p" "$D/queue"); echo $((idx+1)) > "$D/idx"
        arm next "$nxt" "$cur"; echo "item $idx of $n shown (HWND $cur); next item $((idx+1)) armed: on the answer it closes $cur and shows '$nxt'. Ask this item's question NOW (no capture read)."
      else
        if [ -s "$D/transcript" ]; then  # watch only for the last item's question so its shown -> question line is logged too
          nohup python3 -I "$PY" "$(cat "$D/transcript")" last "" "$D" >> "$D/watch.err" 2>&1 &
          echo $! > "$D/pid"
        fi
        echo "item $idx of $n shown (HWND $cur); LAST item: ask its question NOW; after its answer run: evshow.sh end"
      fi
      exit 0
    fi
    exit "${rc:-1}";;
  end)
    D=$(ev_state_dir) || D=""; need_session; export EVSHOW_STATE="$D"
    "$0" disarm >/dev/null 2>&1
    cur=$(cat "$D/current" 2>/dev/null); [ -n "$cur" ] && { "$W" untop "$cur"; "$W" close "$cur"; rm -f "$D/current"; }
    [ -e "$D/zpid" ] && { kill "$(cat "$D/zpid")" 2>/dev/null; pkill -P "$(cat "$D/zpid")" 2>/dev/null; rm -f "$D/zpid"; }
    "$W" close-cloaked   # a cloaked (never shown) window is never left behind
    if [ -s "$D/term" ]; then read -r h l t w ht mx < "$D/term"; echo "saved $h $l $t $w $ht $mx"; "$W" setwin "$h" "$l" "$t" "$w" "$ht" "$mx"; fi
    sleep 1; echo "list-topmost:"; "$W" list-topmost; echo "ended $(et)" >> "$D/history"; rm -f "$D/mode";;
  disarm)
    D=$(ev_state_dir) || { echo "no session"; exit 1; }
    [ -e "$D/pid" ] && { kill "$(cat "$D/pid")" 2>/dev/null; rm -f "$D/pid"; }
    [ -e "$D/gatepid" ] && { kill -- -"$(cat "$D/gatepid")" 2>/dev/null; pkill -P "$(cat "$D/gatepid")" 2>/dev/null; rm -f "$D/gatepid"; }
    echo "disarmed ($(basename "$D"))";;
  status) D=$(ev_state_dir) || { echo "no session"; exit 1; }; echo "state $D"; ls -la "$D"; cat "$D/log" 2>/dev/null;;
  history) D=$(ev_state_dir) || { echo "no session"; exit 1; }; cat "$D/history" 2>/dev/null;;
  *) sed -n '2,26p' "$0"; exit 1;;
esac
