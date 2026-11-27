# bats file_tags=feature:run-agent
# Splits, several launches in one call and the confirm window, each on a tmux server of the test's own.
load ../helpers/common
load ../helpers/run-agent

setup() {
  ra_setup; need_tmux
  mkdir -p "$T/fakebin" "$T/ga" "$T/gb" "$T/gc" "$T/gd"
  cp "$RA_FIX/claude-stay" "$T/fakebin/claude"
  RAW="planner \\\"Plan A\\\" in $T/ga + planner \\\"Plan B\\\" in $T/gb + planner \\\"Plan C\\\" in $T/gc + planner \\\"Plan D\\\" in $T/gd"
}
teardown() { ra_teardown; }

G() { ra_nofds tmux -S "$SK" "$@"; }
sk_prompt() { G capture-pane -p -t "$1" | grep -q '\$ *$'; }
# server <socket name> <session> <PATH prefix> [VAR=value...]: a server of its own; sets SK and CALLER
server() {
  SK="$T/$1"; local s="$2" bin="$3"; shift 3
  ra_nofds env PATH="$bin:$PATH" TMUX= "$@" tmux -S "$SK" -f /dev/null new-session -d -x 200 -y 60 -s "$s" "bash --norc --noprofile" >/dev/null 2>&1
  wait_until 15 sk_prompt "$s"
  CALLER="$(G list-panes -t "$s:0" -F '#{pane_id}')"
}
# type_in <pane> <run-agent arguments as typed>
type_in() { G send-keys -t "$1" "PATH=$T/fakebin:\$PATH '$S' $2" Enter; }
opened() { [ "$(grep -c '^opened' "$1" 2>/dev/null)" -ge "$2" ]; }
panes_are() { [ "$(G list-panes -t "$1" 2>/dev/null | wc -l)" = "$2" ]; }
windows_are() { [ "$(G list-windows -t gp | wc -l)" = "$1" ]; }
caller_alone() { assert_equal "$(G list-panes -t "$1:0" -F '#{pane_id}')" "$CALLER"; }

# old: split: four launches give four new one-pane windows at once (no confirm), caller window unchanged
@test "four split launches give four new one-pane windows at once and leave your window alone" {
  server split.sock sp "$T/fakebin"
  local n=0 p
  for p in A B C D; do
    n=$(( n + 1 ))
    type_in "$CALLER" "--relaunch 'planner \"Plan $p\" in $T split' >> '$T/split.out' 2>&1"
    wait_until 20 opened "$T/split.out" "$n" || { cat "$T/split.out"; return 1; }
  done
  assert_equal "$(G list-windows -t sp -F '#{window_panes}' | tr '\n' ' ')" "1 1 1 1 1 "
  caller_alone sp
  assert_equal "$(grep -c '^opened ' "$T/split.out")" 4
  no grep -q 'confirm there' "$T/split.out"
}

# A scheduled split with confirm: the confirm session's fake claude records into $T/rec.out. Sets SID.
confirm_run() {
  mkdir -p "$T/recbin" "$T/fakehome/.claude/projects/p1"
  ln -s "$T/agents" "$T/fakehome/.claude/agents"
  cp "$RA_FIX/claude-confirm" "$T/recbin/claude"
  # its own server: new windows run with the server's environment (fake claude, fake HOME)
  server confirm.sock sp "$T/recbin" HOME="$T/fakehome" REC_OUT="$T/rec.out"
  G send-keys -t "$CALLER" "'$S' --relaunch 'planner \"Plan A\" in $T/ga at 9pm split confirm' > '$T/rec.launch' 2>&1" Enter
  wait_until 20 test -s "$T/rec.out" || { echo "fake claude never ran"; cat "$T/rec.launch"; G list-windows -t sp; return 1; }
  SID="$(tail -n 1 "$T/rec.out")"
}

# old: confirm: claude --session-id <uuid>
@test "the confirm session is started with a session id of its own" {
  confirm_run
  grep -qx -- '--session-id' "$T/rec.out"
  assert_equal "$(grep -cxF -- "$SID" "$T/rec.out")" 2
  grep -qE '^[0-9a-f-]{36}$' <<<"$SID"
}

# old: confirm: --name 'run-agent: planner ga at 9:00 PM ET'
@test "the confirm session is named after the agent, folder and time" {
  confirm_run
  grep -qx -- '--name' "$T/rec.out"
  grep -qx -- 'run-agent: planner ga at 9:00 PM ET' "$T/rec.out"
}

# old: confirm: prompt carries current time, reset time and the time rules
@test "the confirm prompt carries the current time, the reset time and the time rules" {
  confirm_run
  has "$(head -n 1 "$T/rec.out")" '^You are the /run-agent confirm step'
  has "$(cat "$T/rec.out")" '^Current time: [A-Z][a-z]* 20[0-9-]* [0-9:]* [AP]M ET\. The 5-hour usage window resets at .* ET\.'
  fhas "$T/rec.out" 'tomorrow = the next calendar day'
  fhas "$T/rec.out" 'Never ask when the window ends'
}

gone() { [ ! -e "$1" ]; }

# old: confirm: transcript deleted when the confirm exits
@test "the confirm session's transcript is deleted when it exits" {
  confirm_run
  assert_file_exist "$T/rec.out.transcript-seen"
  wait_until 15 gone "$T/fakehome/.claude/projects/p1/$SID.jsonl"
}

grid_ready() { panes_are gp:1 4 && opened "$T/group.out" 4 && ! G list-panes -t gp:1 -F '#{pane_current_path}' | grep -q 'repo/sub'; }

# old: group: one call gives a new 2x2 window, one planner per folder, caller window unchanged
@test "four planners in one call open a 2x2 window, one per folder, and leave your window alone" {
  server group.sock gp "$T/fakebin"
  type_in "$CALLER" "--group \"$RAW\" > '$T/group.out' 2>&1"
  wait_until 20 grid_ready || { cat "$T/group.out"; return 1; }
  local panes; panes="$(G list-panes -t gp:1 -F '#{pane_left},#{pane_top} #{pane_current_path}')"
  caller_alone gp
  assert_equal "$(printf '%s\n' "$panes" | wc -l)" 4
  assert_equal "$(cut -d, -f1 <<<"$panes" | sort -u | wc -l)" 2
  assert_equal "$(cut -d' ' -f1 <<<"$panes" | cut -d, -f2 | sort -u | wc -l)" 2
  assert_equal "$(awk '{print $2}' <<<"$panes" | xargs -n1 basename | sort | tr '\n' ' ')" "ga gb gc gd "
  windows_are 2
}

group_started() { windows_are 2 && opened "$T/group3.out" 4; }

# old: group: group without confirm runs (four panes at once, no question)
@test "a group without 'confirm' starts all four at once, with no question" {
  server group.sock gp "$T/fakebin"
  type_in "$CALLER" "--relaunch \"$RAW\" > '$T/group3.out' 2>&1"
  wait_until 20 group_started || { cat "$T/group3.out"; return 1; }
  panes_are "$(G list-windows -t gp -F '#{window_id}' | tail -n 1)" 4
  no grep -q 'confirm\|Start 4 sessions' "$T/group3.out"
  caller_alone gp
}

# A group with confirm: sets CP (the confirm pane) and W (its window)
group_confirm() {
  server group.sock gp "$T/fakebin"
  type_in "$CALLER" "--relaunch \"$RAW confirm\" > '$T/group2.out' 2>&1"
  wait_until 20 grep -q '^opened new window' "$T/group2.out" || { cat "$T/group2.out"; return 1; }
  CP="$(grep -o '(%[0-9]*)' "$T/group2.out" | tr -d '()')"
  W="$(G display -p -t "$CP" '#{window_id}')"
}

# old: group: group with confirm asks (confirm opens alone in a new window)
@test "a group with 'confirm' opens only the confirm, alone in a new window" {
  group_confirm
  panes_are "$W" 1
  windows_are 2
  caller_alone gp
}

# old: group: Yes fills the confirm's own window with four panes
@test "saying Yes fills the confirm's own window with four panes" {
  group_confirm
  G respawn-pane -k -t "$CP" "bash --norc --noprofile"
  wait_until 15 sk_prompt "$CP"
  type_in "$CP" "--group --here \"$RAW confirm\""
  wait_until 20 panes_are "$W" 4 || { G list-panes -t "$W"; return 1; }
  caller_alone gp
}
