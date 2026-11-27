# Shared by test/quick/evaluator-*.bats and test/machine/evaluator-*.bats: the evaluator's window and picture
# tools in local-tools/, run against stand-ins in test/fixtures/evaluator-tools/.

LT="$REPO/local-tools"
EVT_FIX="$REPO/test/fixtures/evaluator-tools"

# A temp HOME, a work folder $W (its tmp/ is the TMPDIR of the picture tool) and $T, the common and macOS tools
# side by side as the installed ~/.claude/local-tools has them.
evt_setup() {
  temp_home
  mkdir -p "$BATS_TEST_TMPDIR/w/tmp"
  W="$(cd "$BATS_TEST_TMPDIR/w" && pwd -P)"
  T="$W/tools"
  mkdir "$T"
  local f
  for f in "$LT"/common/* "$LT"/macos/*; do [ -f "$f" ] && ln -sf "$f" "$T/${f##*/}"; done
  return 0
}

# evt <script> [args...]: on a Mac, under /bin/bash (3.2) with an empty environment and the stock PATH, plus the
# tools' own knobs; elsewhere under bash. EVT_PATH adds folders to that PATH.
evt() {
  if [ "$(uname -s)" != Darwin ]; then bash "$@"; return; fi
  local v pass
  pass=()
  for v in $(compgen -e); do
    case "$v" in EVSHOW_*|PHONE_*|FF_*|TMUX_*|OPEN_*) pass[${#pass[@]}]="$v=${!v}";; esac
  done
  env -i HOME="$TEST_HOME" USER="${USER:-runner}" TMPDIR="${TMPDIR:-/tmp}" TERM=xterm-256color LANG=en_US.UTF-8 \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin${EVT_PATH:+:$EVT_PATH}" ${pass[@]+"${pass[@]}"} /bin/bash "$@"
}

# evo <script> [args...]: run it, leave its stdout in $out and its exit status in $rc. The caller asserts both.
# The output goes through a file, so a process the script leaves behind cannot hold the test open.
evo() {
  rc=0
  without_bats_fds evt "$@" >"$W/out" 2>"$W/err" || rc=$?
  out=$(cat "$W/out")
  printf '$ %s -> %s\n%s\n' "$*" "$rc" "$out"
  cat "$W/err"
}

has() { case "$1" in *"$2"*) ;; *) echo "wanted '$2' in: $1"; return 1;; esac; }
lacks() { case "$1" in *"$2"*) echo "did not want '$2' in: $1"; return 1;; esac; }
line1() { printf '%s\n' "$1" | head -n 1; }
alive() { kill -0 "$1" 2>/dev/null; }
gone() { ! kill -0 "$1" 2>/dev/null; }

evt_re() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }

# the number of Firefox processes started with a profile under <state>/ffprof/ (a child with the same command
# line, as a shell stand-in has for a moment, is not counted)
evt_ff_count() {
  local pids p pp n=0
  pids=" $(pgrep -f -- "-profile $(evt_re "$1/ffprof/")" | tr '\n' ' ')"
  for p in $pids; do
    pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -n "$pp" ] || continue
    case "$pids" in *" $pp "*) ;; *) n=$((n + 1));; esac
  done
  echo "$n"
}

# ---- the transcript the readiness watcher follows --------------------------------------------------------------
evt_line() { # <json of one content item> <transcript>
  python3 -c 'import json,sys,datetime; print(json.dumps({"timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"), "message": {"content": [json.loads(sys.argv[1])]}}))' "$1" >> "$2"
}
evt_ask()    { evt_line "{\"type\":\"tool_use\",\"name\":\"AskUserQuestion\",\"id\":\"$1\"}" "$2"; }
evt_answer() { evt_line "{\"type\":\"tool_result\",\"tool_use_id\":\"$1\",\"content\":\"User has answered: \\\"Q\\\"=\\\"$2\\\"\"}" "$3"; }

evt_questions() { local n; n=$(grep -c '^question emitted' "$1/log" 2>/dev/null) || true; echo "${n:-0}"; }
evt_more_questions() { [ "$(evt_questions "$1")" -gt "$2" ]; }

# evt_question <id> <first|next|last> <transcript> <state>: wait for the watcher to follow the transcript, write the
# question, and wait for the watcher to log it. The watcher notes the file's end just after its "following" line, so
# a question written in that instant is written again.
evt_question() {
  wait_until 20 grep -q "watcher: following .* for the $2 answer" "$4/log" || { echo "no watcher for $2"; cat "$4/log"; return 1; }
  local before i
  before=$(evt_questions "$4")
  for i in 1 2 3 4 5 6 7 8 9 10; do
    evt_ask "$1" "$3"
    wait_until 2 evt_more_questions "$4" "$before" && return 0
  done
  echo "the watcher never logged question $1"; cat "$4/log"; return 1
}

# stop whatever a test left: the watcher, and every process whose command line names the work folder
evt_cleanup() {
  [ -n "${W:-}" ] || return 0
  local f
  for f in "$W"/*/pid "$W"/*/item/*.pid; do
    [ -f "$f" ] || continue
    case "$(ps -o command= -p "$(cat "$f")" 2>/dev/null)" in *"$W"*) kill "$(cat "$f")" 2>/dev/null;; esac
  done
  if command -v pkill >/dev/null 2>&1; then pkill -f -- "$(evt_re "$W")" 2>/dev/null; fi
  if [ -s "$W/user.pid" ]; then kill "$(cat "$W/user.pid")" 2>/dev/null; fi
  return 0
}
