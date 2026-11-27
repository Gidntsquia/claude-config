# bats file_tags=feature:run-agent
# Test mode keeps run-agent away from every tmux server but the test's own (a test run once replaced a live pane).
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_clock; unset RUN_AGENT_NOW; need_tmux; OTHER=""; }
teardown() {
  if [ -n "$OTHER" ]; then ra_nofds tmux -S "$OTHER/o.sock" kill-server >/dev/null 2>&1; rm -rf "$OTHER"; fi
  ra_teardown
}

# canary <flag>: a pane on the test's server whose process is named `claude` (so it looks like a live session holding
# TMUX/TMUX_PANE) runs the four hook inputs, in test mode (1) or not (0). Sets BEFORE, the pane's pid.
canary() {
  local cbash=bash
  cp "$RA_FIX/claude-record" "$T/bin/claude"; cp "$RA_FIX/sh-norc" "$T/bin/sh-norc"
  # macOS hides the environment of Apple's own binaries from other processes, and the real claude is not one of
  # them: there the canary runs a re-signed copy of bash, whose environment can be read like claude's.
  if [ "$(uname -s)" = Darwin ]; then cp /bin/bash "$T/cbash"; codesign -s - -f "$T/cbash" >/dev/null 2>&1; cbash="$T/cbash"; fi
  TMUX= TM -f /dev/null new-session -d -x 200 -y 60 -s canary -c "$T/repo/sub" \
    "exec env -u RUN_AGENT_TEST -u RUN_AGENT_TEST_DIR -u RUN_AGENT_FROM -u RUN_AGENT_HUMAN PATH='$T/bin:$PATH' RA_OUT='$T/canary.claude' RUN_AGENT_HOME='$RUN_AGENT_HOME' RUN_AGENT_AGENTS_DIR='$T/agents' RUN_AGENT_USAGE_FILE='$RUN_AGENT_USAGE_FILE' SHELL='$T/bin/sh-norc' bash -c 'exec -a claude $cbash \"\$@\"' _ '$RA_FIX/canary.sh' '$T/canary' $1 '$S' '$T'" >/dev/null 2>&1
  BEFORE="$(pane_pid)"
  [ -n "$BEFORE" ]
}
pane_pid() { TM display -p -t canary '#{pane_pid}' 2>/dev/null; }
replaced() { [ "$(pane_pid)" != "$BEFORE" ]; }
done_or_replaced() { [ -e "$T/canary.done" ] || replaced; }
hook_reason() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['reason'])" "$T/canary.$1"; }

# old: canary: test run inside a claude tmux pane leaves it alone
@test "a test run inside a claude tmux pane leaves that pane alone" {
  canary 1
  wait_until 30 done_or_replaced
  assert_file_exist "$T/canary.done"
  assert_equal "$(pane_pid)" "$BEFORE"
  assert_equal "$(TM display -p -t canary '#{pane_dead}')" 0
  assert_equal "$(basename "$(pargs "$BEFORE" | head -n 1)")" claude
  has "$(hook_reason 4)" '^not inside tmux'
  has "$(hook_reason 1)" '^command: claude --agent worker'
  assert_equal "$(hook_reason 2)" "no scheduled runs"
  has "$(hook_reason 3)" '^command: claude --agent planner'
}

# old: canary: without the flag the pane is replaced (guard is what protects)
@test "without test mode the same run replaces the pane, so the guard is what protects it" {
  canary 0
  wait_until 30 replaced || { cat "$T"/canary.[1-4]; return 1; }
  assert_file_not_exist "$T/canary.done"
}

# A tmux server that is not the test's: socket outside the test folder, not named run-agent-test*.
other_server() {
  OTHER="$(mktemp -d /tmp/ra-o.XXXXXX)"; OTHER="$(cd "$OTHER" && pwd -P)"
  TMUX= ra_nofds tmux -S "$OTHER/o.sock" -f /dev/null new-session -d -s o "bash --norc --noprofile" >/dev/null 2>&1
  OSOCK="$(O display -p '#{socket_path}')"; OPANE="$(O display -p -t o '#{pane_id}')"; OPID="$(O display -p -t o '#{pane_pid}')"
  [ -n "$OPID" ]
}
O() { ra_nofds tmux -S "$OTHER/o.sock" "$@"; }

# old: guard: --relaunch worker on a server that is not the test's -> refused, exit 2, pane untouched
@test "in test mode a pane on someone else's tmux server is not replaced" {
  other_server
  TMUX="$OSOCK,0,0" TMUX_PANE="$OPANE" run ra --relaunch worker
  assert_failure 2
  assert_equal "$(printf '%s\n' "$output" | tail -n 1)" "test mode: refusing tmux respawn-pane on $OSOCK"
  assert_equal "$(O display -p -t o '#{pane_pid}')" "$OPID"
}

# old: guard: split on a server that is not the test's -> no window opened, exit 2
@test "in test mode no window is opened on someone else's tmux server" {
  other_server
  TMUX="$OSOCK,0,0" TMUX_PANE="$OPANE" run ra --relaunch "planner \"x\" in $T/sibling split"
  assert_failure 2
  grep -qxF "test mode: refusing tmux new-window on $OSOCK" <<<"$output"
  assert_equal "$(O list-windows -t o | wc -l)" 1
}

# old: guard: the default server's socket is refused
@test "in test mode a socket named like the default server is refused" {
  # a socket path of the default server's shape, in a folder of the test's making: if the guard ever broke, the
  # command would find no server there instead of reaching yours
  OTHER="$(mktemp -d /tmp/ra-o.XXXXXX)"; OTHER="$(cd "$OTHER" && pwd -P)"
  local sock; sock="$OTHER/tmux-$(id -u)/default"
  TMUX="$sock,1,0" TMUX_PANE="%0" run ra --relaunch worker
  assert_failure 2
  assert_equal "$(printf '%s\n' "$output" | tail -n 1)" "test mode: refusing tmux respawn-pane on $sock"
}
