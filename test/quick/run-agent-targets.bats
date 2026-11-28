# bats file_tags=feature:run-agent
# Launch targets, the run-agent shell command, the next-step lines and the /run-agent hook.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_clock; BIN="$REPO/bin/run-agent"; }
teardown() { ra_teardown; }

# parsed <raw> <python expression about d>
parsed() {
  local out; out="$(ra --parse "$1")"
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert $2, d" "$out"
}
# under_claude <agent that is running> <shell line>: run it as a child of a "claude --agent X --model opus --effort high"
under_claude() { (exec -a claude bash -c "$2; true" _ --agent "$1" --model opus --effort high); }
no_model_flags() { no grep -q -- '--model\|--effort\|opus\|high' <<<"$1"; }

# old: target: split parsed
@test "'split' after a launch asks for a split" {
  parsed 'planner "Plan A" in /tmp split' "d['target']=='split' and '--target split' in d['run'] and d['dir']=='/tmp' and not d['unsure']"
}

# old: target: new window parsed
@test "'new window' after a launch asks for a new window" { parsed 'worker new window' "d['target']=='window'"; }

# old: target: 'after window' stays a time
@test "'after window' is read as a time, not as a window target" {
  parsed 'worker after window' "'target' not in d and d['at_text']=='after window'"
}

# old: bin/run-agent: dry prints command, dir, time
@test "the run-agent shell command's dry run prints command, folder and time" {
  run ra_nofds "$BIN" worker "." in "$T" dry </dev/null
  has "$output" '^command: claude --agent worker'
  has "$output" '^dir: '
  has "$output" '^run at: now'
}

# old: bin/run-agent: --jobs and --next go to the script as flags (no which-agent question)
@test "the run-agent shell command passes --jobs and --next through as flags" {
  assert_equal "$(ra_nofds "$BIN" --jobs </dev/null 2>&1)" "no scheduled runs"
  has "$(ra_nofds "$BIN" --next evaluator "." </dev/null 2>&1)" '^/run-agent evaluator "\."$'
}

# old: next: short sentence, /run-agent line, labelled claude line, three lines
@test "the next step is three lines: a short sentence, the /run-agent line and the claude line" {
  run ra --next planner "Replan based on plans/EVAL.md"
  assert_equal "${#lines[@]}" 3
  has "${lines[0]}" '^Next,.*replan.*:$'
  [ "${#lines[0]}" -le 60 ]
  has "${lines[1]}" '^/run-agent planner "Replan based on plans/EVAL.md"'
  no grep -q claude <<<"${lines[1]}"
  has "${lines[2]}" '^Without run-agent: claude --agent planner "Replan based on plans/EVAL.md"'
}

# old: next: evaluator phone sentence
@test "the next step for a phone evaluation says it runs on your phone" {
  has "$(ra --next evaluator phone)" '^Next, .*evaluator on your phone:$'
}

# old: next worker: no model/effort even from an opus high session
@test "the next worker lines carry no model or effort from the running session" {
  local out; out="$(under_claude evaluator "'$S' --next worker .")"
  assert_equal "$(printf '%s\n' "$out" | wc -l)" 3
  has "$out" '^Next, after reading this eval, rerun the worker'
  grep -qx '/run-agent worker "."' <<<"$out"
  grep -qx 'Without run-agent: CLAUDE_CODE_SUBAGENT_MODEL=sonnet CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 claude --agent worker "."' <<<"$out"
}

# old: next evaluator: no model/effort even from an opus high session
@test "the next evaluator lines carry no model or effort from the running session" {
  local out; out="$(under_claude worker "'$S' --next evaluator .")"
  grep -qx '/run-agent evaluator "."' <<<"$out"
  grep -qx 'Without run-agent: claude --agent evaluator "."' <<<"$out"
}

# next_named <agent>
next_named() {
  local out; out="$(under_claude evaluator "'$S' --next $1 'Replan based on plans/EVAL.md'")"
  grep -qx "/run-agent $1 \"Replan based on plans/EVAL.md\"" <<<"$out"
  grep -qx "Without run-agent: claude --agent $1 \"Replan based on plans/EVAL.md\"" <<<"$out"
  no_model_flags "$out"
}

# old: next planner: no model/effort even from an opus high session
@test "the next planner lines carry no model or effort from the running session" { next_named planner; }

# old: next helper: no model/effort even from an opus high session
@test "the next helper lines carry no model or effort from the running session" { next_named helper; }

reason() { python3 -c "import json,sys; print(json.loads(sys.argv[1])['reason'])" "$1"; }

# old: hook: --hook blocks the expansion with the script's output, prompt suppressed
@test "typing /run-agent is answered by the script, with no model turn" {
  local out
  out="$(printf '{"command_name":"run-agent","command_args":"worker \\"x\\" in %s dry","prompt":"/run-agent worker"}' "$T/sibling" | ra --hook)"
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['decision']=='block' and d['hookSpecificOutput']=={'hookEventName':'UserPromptExpansion','suppressOriginalPrompt':True} and d['reason'].startswith('command: claude --agent worker \"x\"') and 'dry run' in d['reason'], d" "$out"
}

# old: hook: jobs
@test "/run-agent jobs answers with the job list" {
  assert_equal "$(reason "$(printf '{"command_args":"jobs"}' | ra --hook)")" "no scheduled runs"
}

# old: hook: outside tmux -> the run-agent line to type
@test "/run-agent outside tmux answers with the line to type" {
  has "$(reason "$(printf '{"command_args":"worker"}' | ra --hook)")" '^not inside tmux'
}

# old: hook: a typed /run-agent inside an agent session is the human's (split kept)
@test "/run-agent typed inside an agent session counts as the person's, not the agent's" {
  local out r
  out="$( (exec -a claude bash -c "printf '{\"command_args\":\"planner \\\\\"x\\\\\" in $T/sibling split dry\"}' | env -u RUN_AGENT_HUMAN -u RUN_AGENT_FROM '$S' --hook; true" _ --agent worker) )"
  r="$(reason "$out")"
  has "$r" 'claude --agent planner'
  no grep -q '^ignored' <<<"$r"
}

# old: hook: settings.json has the run-agent UserPromptExpansion hook, timeout >= 60 s
@test "settings.json runs the /run-agent hook with at least 60 s to answer" {
  python3 -c "import json,sys; s=json.load(open(sys.argv[1])); hs=s['hooks']['UserPromptExpansion']; h=[x for x in hs if x['matcher']=='run-agent'][0]['hooks'][0]; assert 'run-agent.sh' in h['command'] and h['command'].endswith('--hook') and h['timeout']>=60, h" "$REPO/settings.json"
}
