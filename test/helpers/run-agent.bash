# Shared by test/quick/run-agent-*.bats.
#
# Each test gets a folder of its own, "$T" (short, under /tmp: a tmux socket path has a length limit), holding
# the job store, a git repo, sibling folders, fake agents and every tmux socket (TMUX_TMPDIR). The caller's
# claude, tmux and run-agent variables are removed, so a test run from inside an agent session behaves like one
# run from a plain shell, and no tmux command can reach the server of the person running the suite.
RA_SRC="$REPO/skills/run-agent/scripts"
RA_FIX="$REPO/test/fixtures/run-agent"

ra_setup() {
  local v a
  # run-agent needs tmux and a Unix process table; its tests never ran on Windows.
  if ra_on_windows; then skip "run-agent needs tmux, which Windows Git Bash lacks"; fi
  for v in $(compgen -e); do
    case "$v" in CLAUDE*|TMUX*|ANTHROPIC*|RUN_AGENT_*) unset "$v" ;; esac
  done
  temp_home
  T="$(mktemp -d /tmp/ra.XXXXXX)" || return 1
  T="$(cd "$T" && pwd -P)" || return 1
  S="$RA_SRC/run-agent.sh"
  SOCK="run-agent-test-$$-$BATS_TEST_NUMBER"
  export RUN_AGENT_TEST=1 RUN_AGENT_TEST_DIR="$T" RUN_AGENT_HOME="$T/home" TMUX_TMPDIR="$T"
  export RUN_AGENT_HUMAN=1 PYTHONDONTWRITEBYTECODE=1 SHELL=/bin/sh TERM=xterm-256color
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
  mkdir -p "$T/repo/sub" "$T/sibling" "$T/my project" "$T/bin" "$T/agents" "$T/path"
  for a in worker:sonnet planner:fable evaluator:opus helper:opus; do
    printf -- '---\nmodel: %s\n---\n' "${a#*:}" > "$T/agents/${a%:*}.md"
  done
  export RUN_AGENT_AGENTS_DIR="$T/agents"
  # No test reaches a real claude: this one fails loudly. A test that needs a fake puts its own in "$T/bin".
  printf '#!/bin/sh\necho "stub claude was run: $*" >&2\nexit 99\n' > "$T/path/claude"
  chmod +x "$T/path/claude"
  if [ "$(uname -s)" = Darwin ]; then
    # What a stock Mac has (test/helpers/stock-mac.sh): /bin/bash 3.2 and the system tools, plus tmux.
    v="$(command -v tmux)" && ln -s "$v" "$T/path/tmux"
    export PATH="$T/path:/usr/bin:/bin:/usr/sbin:/sbin" LANG=en_US.UTF-8
    unset LC_ALL
  else
    export PATH="$T/path:$PATH" LC_ALL=C.UTF-8
  fi
  git -C "$T/repo" init -q || return 1
  cd "$T/repo/sub" || return 1
}

# Kill everything this test started: the runners named in any job store under "$T" (each leads its own process
# group, with its sleep in it), every tmux server whose socket is under "$T", and any process naming "$T".
ra_teardown() {
  [ -n "${T:-}" ] && [ -d "$T" ] || return 0
  local pid s
  cd / || return 1
  for pid in $(ra_runner_pids); do ra_kill_runner "$pid"; done
  if command -v tmux >/dev/null 2>&1; then
    find "$T" -type s 2>/dev/null | while IFS= read -r s; do tmux -S "$s" kill-server >/dev/null 2>&1; done
  fi
  ps -A -o pid=,command= 2>/dev/null | grep -F "$T/" | grep -v grep | while read -r pid s; do
    [ "$pid" != "$$" ] && kill -9 "$pid" 2>/dev/null
  done
  # A runner killed on its own (the revive and pane-gone cases do that) leaves its sleep behind, and a sleep names
  # no folder in its arguments: it is found by its working directory.
  for pid in $(ra_inside "$T"); do kill -9 "$pid" 2>/dev/null; done
  rm -rf "$T" 2>/dev/null || rm -rf "$T"
  return 0
}

# ra_inside <folder>: pids of processes whose working directory is inside the folder, this shell's own excluded.
ra_inside() {
  local dir p
  dir="$(cd "$1" && pwd -P)" || return 0
  if [ -d /proc/self ]; then
    for p in /proc/[0-9]*; do
      case "$(readlink "$p/cwd" 2>/dev/null)" in "$dir"|"$dir"/*) [ "${p#/proc/}" = "$$" ] || echo "${p#/proc/}" ;; esac
    done
  else
    lsof -a -c '/^sleep$/' -d cwd -Fpn 2>/dev/null | D="$dir/" awk '/^p/ { p = substr($0, 2) } /^n/ && index(substr($0, 2) "/", ENVIRON["D"]) == 1 { print p }'
  fi
}

ra_runner_pids() {
  cat "$T/runners" 2>/dev/null
  [ -n "$(find "$T" -name '*.json' -path '*/[jd]o[bn]*' 2>/dev/null | head -n 1)" ] || return 0
  find "$T" \( -path '*/jobs/*.json' -o -path '*/done/*.json' \) -type f 2>/dev/null | python3 -c '
import json, sys
for f in sys.stdin.read().splitlines():
    try:
        p = int(json.load(open(f)).get("pid") or 0)
    except Exception:
        continue
    if p > 1:
        print(p)'
}

# ra_kill_runner <pid>: the runner's whole process group, only while <pid> still is a run-agent runner.
ra_kill_runner() {
  [ "$1" -gt 1 ] 2>/dev/null || return 0
  case "$(ps -p "$1" -o command= 2>/dev/null)" in
    *runner.sh*) kill -9 -- "-$1" 2>/dev/null || kill -9 "$1" 2>/dev/null ;;
  esac
  return 0
}

# Anything run-agent starts may leave a runner or a tmux server behind: no bats descriptor goes with it.
ra() { ra_nofds "$S" "$@"; }
# Like without_bats_fds (proc.bash) but stderr survives: that one redirects its loop to /dev/null and then closes
# the descriptor bash saved the real stderr in, so everything the command writes to stderr is lost.
ra_nofds() {
  (
    for _fd in 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do eval "exec $_fd>&-"; done
    "$@"
  )
}

# no <command...>: succeeds when the command fails (`! cmd` does not fail a test in bash 3.2).
no() { if "$@"; then echo "expected to fail: $*" >&2; return 1; fi; }

# line <n> <text>: line n of the text.
line() { printf '%s\n' "$2" | sed -n "$1p"; }

# ra_check <want exit> <want last line> <run-agent arguments...>
ra_check() {
  local want_rc="$1" want="$2"; shift 2
  run ra "$@"
  assert_equal "$status" "$want_rc"
  assert_equal "$(printf '%s\n' "$output" | tail -n 1)" "$want"
}

# ---- clock, usage API, parse ----------------------------------------------------------------------------------
# ep '<YYYY-MM-DD HH:MM>': that New York wall-clock time as an epoch (BSD date has no -d).
ep() { python3 -c 'import sys, datetime, zoneinfo; print(int(datetime.datetime.strptime(sys.argv[1], "%Y-%m-%d %H:%M").replace(tzinfo=zoneinfo.ZoneInfo("America/New_York")).timestamp()))' "$1"; }
# mtime <epoch> <file>...: set the files' modification time
mtime() { python3 -c 'import os, sys
for f in sys.argv[2:]:
    open(f, "a").close(); os.utime(f, (int(sys.argv[1]),) * 2)' "$@"; }
# pargs <pid>: the process's arguments, one per line
pargs() { python3 "$RA_SRC/proc.py" argv "$1"; }
# BSD wc pads its count with spaces, GNU does not
wc() { command wc "$@" | tr -d ' '; }

# Frozen clock 2026-10-22 18:00 ET; a fake usage API with the window resetting at 8:20 PM ET.
ra_clock() {
  export RUN_AGENT_TZ=America/New_York RUN_AGENT_TEST_PID=$$
  RUN_AGENT_NOW=1792706400   # ep '2026-10-22 18:00'
  export RUN_AGENT_NOW RUN_AGENT_USAGE_FILE="$T/usage.json"
  printf '{"five_hour":{"utilization":29.0,"resets_at":"2026-10-23T00:20:00.251269+00:00"}}' > "$T/usage.json"
}

# Values the parse tests share: overrides for a launch with typed flags, and the reset time of the fake API.
FL='"flags":"--model fable --effort medium","command":"claude --agent worker \".\" --model fable --effort medium --name \"worker: repo (fable)\"","run":"S worker . -- --model fable --effort medium"'
FLOW='"flags":"--model fable --effort low","command":"claude --agent worker \".\" --model fable --effort low --name \"worker: repo (fable)\"","run":"S worker . -- --model fable --effort low"'
RESET='"reset":1792714800,"reset_shown":"8:20 PM ET"'
FLJ='"flags":"--model fable --effort low","command":"claude --agent worker \".\" --model fable --effort low --name \"worker: repo (fable)\"","_run":"-- --model fable --effort low"'

# pcheck <raw> <json overrides>: the --parse output is exactly the base object plus the overrides.
pcheck() {
  local got diff
  got="$(ra --parse "$1" 2>&1)"
  diff="$(printf '%s' "$got" | python3 "$RA_FIX/pcheck.py" "$2")" || { echo "pcheck.py failed on: $got"; return 1; }
  [ -z "$diff" ] || { printf '%s\n' "--parse $1" "$diff"; return 1; }
}

# tcheck <raw> <epoch> <at_text> <derived text or ""> [<extra json>]: an at + at_shown + run (+ --at-shown)
tcheck() {
  local over
  over="$(python3 "$RA_FIX/tover.py" "$RA_SRC" "$2" "$3" "$4" "${5:-}" "{$RESET}")" || return 1
  pcheck "$1" "$over"
}

# pcases: a case list on stdin, one case a line: `<what is typed> => <json overrides>`, each checked by pcheck.
# `\n` in the typed part is a line break; empty lines and lines starting with # are skipped. `case: <typed>` is
# printed before each case: test/run puts the last one in the FAILED line, so a failure names its case.
pcases() { ra_cases pcheck; }
# tcases: the same for tcheck: `<what is typed> => <epoch or YYYY-MM-DD HH:MM ET> | <at_text> [| <derived text> [| <extra json>]]`
tcases() { ra_cases ra_tcase; }
ra_tcase() {
  local when text shown extra
  IFS='|' read -r when text shown extra <<<"$2"
  when="$(ra_trim "$when")"
  case "$when" in ????-??-??\ ??:??) when="$(ep "$when")" ;; esac
  tcheck "$1" "$when" "$(ra_trim "$text")" "$(ra_trim "$shown")" "$(ra_trim "$extra")"
}
ra_trim() { local v="$1"; v="${v#"${v%%[! ]*}"}"; printf '%s' "${v%"${v##*[! ]}"}"; }
# ra_cases <check>: the list is read whole first, so nothing a case runs can eat the rest of it.
ra_cases() {
  local l list=() n=0 nl='
'
  while IFS= read -r l; do
    case "$l" in ''|'#'*) continue ;; esac
    case "$l" in *' => '*) ;; *) echo "not a case line (wanted: <typed> => <expected>): $l"; return 1 ;; esac
    list[${#list[@]}]="$l"
  done
  [ "${#list[@]}" -gt 0 ] || { echo "an empty case list"; return 1; }
  for l in "${list[@]}"; do
    echo "case: ${l%% => *}"
    "$1" "$(ra_typed "${l%% => *}" "$nl")" "${l#* => }" || return 1
  done
}
ra_typed() { local v="$1"; printf '%s' "${v//\\n/$2}"; }

# ---- tmux ------------------------------------------------------------------------------------------------------
need_tmux() {
  if ra_on_windows; then skip "run-agent needs tmux, which Windows Git Bash lacks"; fi
  command -v tmux >/dev/null 2>&1 || { echo "tmux is missing" >&2; return 1; }
}
ra_on_windows() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac; }
TM() { ra_nofds tmux -L "$SOCK" "$@"; }

# has <text> <grep regex>: a line of the text matches; shows the text when none does.
has() { grep -q -- "$2" <<<"$1" || { printf 'no line matches: %s\nin:\n%s\n' "$2" "$1" >&2; return 1; }; }
# fhas <file> <grep regex>
fhas() { grep -q -- "$2" "$1" 2>/dev/null || { printf 'no line matches: %s\nin %s:\n' "$2" "$1" >&2; cat "$1" >&2; return 1; }; }

# ---- scheduling in a private tmux server ------------------------------------------------------------------------
SHOWN='claude --agent worker "." --model fable --name "worker: repo (fable)"'
# Real clock, a fake claude that records its start, and one tmux session "t" running a plain shell in repo/sub.
ra_tmux_setup() {
  need_tmux
  cp "$RA_FIX/claude-record" "$T/bin/claude"
  cp "$RA_FIX/sh-norc" "$T/bin/sh-norc"
  export RA_OUT="$T/claude.out" RUN_AGENT_TZ=America/New_York RUN_AGENT_USAGE_FILE="$T/usage.json" RUN_AGENT_TEST_PID=$$
  export RUN_AGENT_NO_RETRY=1
  J="$RA_SRC/jobs.py"
  LOG="$RUN_AGENT_HOME/jobs.log"
  mkdir -p "$RUN_AGENT_HOME"
  usage_at $(( $(date +%s) + 7200 ))
  # The server carries the fake PATH and RA_OUT, so panes respawned by the detached runner see them too.
  PANE_ENV="env PATH='$T/bin:$PATH' RA_OUT='$RA_OUT' RUN_AGENT_HOME='$RUN_AGENT_HOME' RUN_AGENT_USAGE_FILE='$RUN_AGENT_USAGE_FILE' RUN_AGENT_TZ=America/New_York SHELL='$T/bin/sh-norc'"
  ra_server
}
ra_server() {
  PATH="$T/bin:$PATH" SHELL="$T/bin/sh-norc" TMUX= TM -f /dev/null new-session -d -s t -c "$T/repo/sub" "$PANE_ENV bash --norc --noprofile" >/dev/null 2>&1 || return 1
  ra_ready t
}
ra_prompt() { TM capture-pane -p -t "$1" | grep -q '\$ *$'; }
ra_ready() { wait_until 15 ra_prompt "$1" || { echo "no shell prompt in pane $1" >&2; return 1; }; }
# keys <command line>: type it into pane $TARGET (default: session t) and press Enter
keys() { TM send-keys -t "${TARGET:-t}" "$1" Enter; }
# usage_at <epoch>: the fake usage API now reports that reset time
usage_at() { python3 -c "import json,datetime,sys; print(json.dumps({'five_hour':{'utilization':1.0,'resets_at':datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).isoformat()}}))" "$1" > "$RUN_AGENT_USAGE_FILE"; }
jget() { python3 "$RA_SRC/jobs.py" get "$1" "$2"; }
ra_asleep_now() { local p; p="$(jget "$1" pid)"; [ -n "$p" ] && [ "$p" != 0 ]; }
# ra_asleep <id>: wait until the job's runner pid is recorded
ra_asleep() { wait_until 15 ra_asleep_now "$1" || { echo "job $1 has no runner" >&2; return 1; }; }
ra_dead_now() { no kill -0 "$1" 2>/dev/null; }
ra_dead() { wait_until 15 ra_dead_now "$1" || { echo "pid $1 is still alive" >&2; return 1; }; }
# ra_id <file>: wait for the "scheduled #N:" line in the file, set ID
ra_id() {
  wait_until 20 grep -q '^scheduled #[0-9]' "$1" || { echo "nothing scheduled:" >&2; cat "$1" >&2; return 1; }
  ID="$(sed -n 's/^scheduled #\([0-9]*\):.*/\1/p' "$1")"
}
# logged <seconds> <regex>: wait for a jobs.log line
logged() { wait_until "$1" grep -q -- "$2" "$LOG" || { printf 'jobs.log has no: %s\n' "$2" >&2; cat "$LOG" "$RUN_AGENT_HOME"/logs/*.log >&2; return 1; }; }
# claude_ran <regex>: wait for the fake claude's record
claude_ran() { wait_until 15 grep -q -- "$1" "$RA_OUT" || { printf 'fake claude record has no: %s\n' "$1" >&2; cat "$RA_OUT" >&2; TM capture-pane -p -t t >&2; return 1; }; }
