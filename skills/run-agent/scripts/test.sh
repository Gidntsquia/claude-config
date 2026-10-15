#!/usr/bin/env bash
# test.sh: self-test for run-agent.sh's directory option. Runs the script with TMUX unset from a temp git
# repo (printed command + exit codes), then once inside a private tmux server (`tmux -L run-agent-test-$$`,
# fake `claude` on PATH) to check the respawned pane starts in the target dir. Never touches your tmux.
# Prints "N passed, M failed"; exit 1 on any failure.
set -uo pipefail

S="$(cd "$(dirname "$0")" && pwd)/run-agent.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; }

T=$(mktemp -d); T=$(cd "$T" && pwd -P)
SOCK="run-agent-test-$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

# Layout: $T/repo (git repo, cwd for the tests) with repo/sub; siblings $T/sibling and "$T/my project".
mkdir -p "$T/repo/sub" "$T/sibling" "$T/my project" "$T/bin"
git -C "$T/repo" init -q
cd "$T/repo/sub"

# check <label> <want-rc> <want-output-line> <args...>: runs S with TMUX unset, compares rc and last line.
check() {
  local label="$1" want_rc="$2" want="$3"; shift 3
  local out rc
  out=$(env -u TMUX -u TMUX_PANE "$S" "$@" 2>&1); rc=$?
  if [ "$rc" != "$want_rc" ]; then bad "$label" "rc $rc, want $want_rc; output: $out"
  elif [ "$(printf '%s\n' "$out" | tail -n 1)" != "$want" ]; then bad "$label" "got:  $(printf '%s\n' "$out" | tail -n 1)
     want: $want"
  else ok "$label"
  fi
}

# (a) existing dir, absolute and relative
check "a: existing absolute dir" 1 \
  "cd '$T/sibling' && claude --agent planner \"x\" --name \"planner: sibling\"" planner x --cwd "$T/sibling"
check "a: existing relative dir with /, -C" 1 \
  "cd '$T/sibling' && claude --agent worker \".\" --name \"worker: sibling\"" worker -C ../../sibling
check "a: dir with a space, --cwd= form, model" 1 \
  "cd '$T/my project' && claude --agent worker \"go\" --model opus --name \"worker: my project (opus)\"" \
  worker go "--cwd=$T/my project" -- --model opus
check "a: ~ expands to \$HOME" 1 \
  "cd '$HOME' && claude --agent worker \".\" --name \"worker: $(basename "$HOME")\"" worker --cwd '~'
# (b) bare name: sibling of the git root, then a name under the cwd wins over the sibling
check "b: bare name = sibling of the git root" 1 \
  "cd '$T/sibling' && claude --agent worker \".\" --name \"worker: sibling\"" worker --cwd sibling
mkdir -p "$T/repo/sub/sibling"
check "b: bare name under the cwd wins" 1 \
  "cd '$T/repo/sub/sibling' && claude --agent worker \".\" --name \"worker: sibling\"" worker --cwd sibling
rmdir "$T/repo/sub/sibling"
check "b: bare name found nowhere" 2 \
  "no such directory: nope-xyz (looked in $T/repo/sub, $T)" worker --cwd nope-xyz
# (c) missing dir / a file
check "c: missing absolute dir -> exit 2" 2 "no such directory: $T/missing" worker --cwd "$T/missing"
check "c: missing ~ dir -> exit 2" 2 "no such directory: $HOME/no-such-run-agent-dir-$$" worker --cwd "~/no-such-run-agent-dir-$$"
touch "$T/afile"
check "c: a file -> not a directory" 2 "not a directory: $T/afile" worker --cwd "$T/afile"
[ ! -e "$T/missing" ] && [ ! -e "$HOME/no-such-run-agent-dir-$$" ] && ok "c: nothing created" || bad "c: nothing created"
# (d) no dir: unchanged behaviour
check "d: no dir, name from git root" 1 "claude --agent worker \".\" --name \"worker: repo\"" worker
check "d: no dir, model" 1 "claude --agent planner \"x\" --model opus --name \"planner: repo (opus)\"" planner x -- --model opus
check "d: planner without a prompt -> no prompt argument" 1 "claude --agent planner --name \"planner: repo\"" planner
check "d: planner without a prompt, with a dir" 1 \
  "cd '$T/sibling' && claude --agent planner --name \"planner: sibling\"" planner --cwd "$T/sibling"
LAST_USAGE="                         bare name found nowhere, or a path that is a file); creates nothing"
check "d: extra word -> usage" 2 "$LAST_USAGE" worker . extra
# (e) --name given
check "e: --name wins over the dir name" 1 \
  "cd '$T/sibling' && claude --agent worker \"x\" --name \"mine\"" worker x --cwd "$T/sibling" -- --name mine
check "two dirs -> usage" 2 "$LAST_USAGE" worker --cwd a -C b
# --resolve
out=$("$S" --resolve "$T/repo/./sub/../sub/" 2>&1)
[ "$out" = "$T/repo/sub	exists" ] && ok "resolve: . and .. collapsed" || bad "resolve: . and .. collapsed" "$out"
out=$("$S" --resolve "~/no-such-run-agent-dir-$$" 2>&1)
[ "$out" = "$HOME/no-such-run-agent-dir-$$	missing" ] && ok "resolve: missing path" || bad "resolve: missing path" "$out"

# Inside tmux (private server): the respawned pane and claude start in the target dir.
if command -v tmux >/dev/null; then
  cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
{ echo "pwd=$PWD"; printf 'arg=%s\n' "$@"; } > "$RA_OUT"
EOF
  chmod +x "$T/bin/claude"
  export RA_OUT="$T/claude.out"
  tmux -L "$SOCK" -f /dev/null new-session -d -s t -c "$T/repo/sub" \
    "env PATH='$T/bin:$PATH' RA_OUT='$RA_OUT' SHELL=/bin/bash bash --norc --noprofile"
  sleep 0.5
  tmux -L "$SOCK" send-keys -t t "'$S' planner 'curl it' --cwd '$T/my project'" Enter
  for _ in $(seq 1 40); do [ -s "$RA_OUT" ] && break; sleep 0.25; done
  sleep 0.5
  if [ -s "$RA_OUT" ] && grep -qxF "pwd=$T/my project" "$RA_OUT"; then ok "tmux: claude started in the dir"
  else bad "tmux: claude started in the dir" "$(cat "$RA_OUT" 2>/dev/null)"; fi
  grep -qxF "arg=planner: my project" "$RA_OUT" 2>/dev/null && ok "tmux: --name \"planner: my project\" is one argument" \
    || bad "tmux: --name argument" "$(cat "$RA_OUT" 2>/dev/null)"
  p=$(tmux -L "$SOCK" display -p -t t '#{pane_current_path}')
  [ "$p" = "$T/my project" ] && ok "tmux: pane_current_path is the dir" || bad "tmux: pane_current_path" "$p"
  dead=$(tmux -L "$SOCK" display -p -t t '#{pane_dead}')
  [ "$dead" = 0 ] && ok "tmux: shell left in the pane" || bad "tmux: shell left in the pane" "pane_dead=$dead"
else
  echo "SKIP tmux checks (tmux not installed)"
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
