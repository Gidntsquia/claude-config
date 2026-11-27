#!/usr/bin/env bats
# What /run-agent understands from logged argument strings, typos and word mappings.
# Each --parse test compares the whole JSON answer: a frozen clock (2026-10-22 6:00 PM ET), a fake usage API.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_clock; export RUN_AGENT_NO_RETRY=1; }
teardown() { ra_teardown; }

# bats file_tags=feature:run-agent
AT9_FLOW='"at":1792717200,"at_text":"at 9pm","at_shown":"9:00 PM ET (at 9pm, in 3h 0m)","run":"S worker . --at 1792717200 --at-text '"'"'at 9pm'"'"' -- --model fable --effort low"'
EVP='"agent":"evaluator","prompt":"I’m on my phone","command":"claude --agent evaluator \"I’m on my phone\" --name \"evaluator: repo (opus)\"","run":"S evaluator '"'"'I’m on my phone'"'"'"'

# old: parse: log: key=value, spaced =, commas
@test "/run-agent log: key=value, spaced =, commas" {
  pcheck 'worker, model=fable effort = medium,' "{$FL}"
}

# old: parse: log: key=value, spaced =, commas, confirm
@test "/run-agent log: key=value, spaced =, commas, confirm" {
  pcheck 'worker, model=fable effort = medium, confirm' "{$FL,\"confirm\":1}"
}

# old: parse: log: effort =medium
@test "/run-agent log: effort =medium" {
  pcheck 'worker model=fable effort =medium' "{$FL}"
}

# old: parse: log: em dashes
@test "/run-agent log: em dashes" {
  pcheck 'worker —model fable —effort low' "{$FLOW}"
}

# old: parse: log: single dashes
@test "/run-agent log: single dashes" {
  pcheck 'worker -model fable -effort low' "{$FLOW}"
}

# old: parse: log: bare model + '<effort> effort'
@test "/run-agent log: bare model + '<effort> effort'" {
  pcheck 'worker fable low effort' "{$FLOW}"
}

# old: parse: log: model+effort
@test "/run-agent log: model+effort" {
  pcheck 'worker, opus+medium effort' '{"flags":"--model opus --effort medium","command":"claude --agent worker \".\" --model opus --effort medium --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --effort medium"}'
}

# old: parse: log: commas everywhere
@test "/run-agent log: commas everywhere" {
  pcheck 'worker, model=fable, effort=medium,' "{$FL}"
}

# old: parse: log: confirm before em-dash flags
@test "/run-agent log: confirm before em-dash flags" {
  pcheck 'worker confirm —model fable —effort medium' "{$FL,\"confirm\":1}"
}

# old: parse: log: curly quotes
@test "/run-agent log: curly quotes" {
  pcheck 'evaluator “I’m on my phone”' '{"agent":"evaluator","prompt":"I’m on my phone","command":"claude --agent evaluator \"I’m on my phone\" --name \"evaluator: repo (opus)\"","run":"S evaluator '"'"'I’m on my phone'"'"'"}'
}

# old: parse: log: claude --agent evaluator "."
@test "/run-agent log: claude --agent evaluator '.'" {
  pcheck 'claude --agent evaluator "."' '{"agent":"evaluator","command":"claude --agent evaluator \".\" --name \"evaluator: repo (opus)\"","run":"S evaluator ."}'
}

# old: parse: log: newline inside the prompt
@test "/run-agent log: newline inside the prompt" {
  pcheck 'planner "line one
line two" --model opus' '{"agent":"planner","prompt":"line one\nline two","flags":"--model opus","command":"claude --agent planner \"line one\nline two\" --model opus --name \"planner: repo (opus)\"","run":"S planner '"'"'line one\nline two'"'"' -- --model opus"}'
}

# old: parse: sessions: haiku usage error on 'model=fable effort =medium'
@test "/run-agent sessions: haiku usage error on 'model=fable effort =medium'" {
  pcheck 'worker model=fable effort =medium' "{$FL}"
}

# old: parse: sessions: haiku usage error on em-dash flags
@test "/run-agent sessions: haiku usage error on em-dash flags" {
  pcheck 'worker —model fable —effort low' "{$FLOW}"
}

# old: parse: sessions: haiku 'not run' on single-dash flags
@test "/run-agent sessions: haiku 'not run' on single-dash flags" {
  pcheck 'worker -model fable -effort low' "{$FLOW}"
}

# old: parse: sessions: haiku dropped 'low effort'
@test "/run-agent sessions: haiku dropped 'low effort'" {
  pcheck 'worker fable low effort' "{$FLOW}"
}

# old: parse: sessions: haiku 'could not parse' bare model + em-dash effort
@test "/run-agent sessions: haiku 'could not parse' bare model + em-dash effort" {
  pcheck 'worker fable —effort low' "{$FLOW}"
}

# old: parse: sessions: haiku dry run
@test "/run-agent sessions: haiku dry run" {
  pcheck 'worker fable low effort at 9pm dry' "{\"flags\":\"--model fable --effort low\",\"command\":\"claude --agent worker \\\".\\\" --model fable --effort low --name \\\"worker: repo (fable)\\\"\",\"dry\":1,$AT9_FLOW,$RESET}"
}

# old: parse: sessions: full claude command with em-dash flags
@test "/run-agent sessions: full claude command with em-dash flags" {
  pcheck 'claude --agent worker "." —model fable —effort medium' "{$FL}"
}

# old: parse: sessions: full claude command, capital Confirm
@test "/run-agent sessions: full claude command, capital Confirm" {
  pcheck 'claude --agent evaluator "." Confirm' '{"agent":"evaluator","confirm":1,"command":"claude --agent evaluator \".\" --name \"evaluator: repo (opus)\"","run":"S evaluator ."}'
}

# old: parse: sessions: full claude command, trailing dot
@test "/run-agent sessions: full claude command, trailing dot" {
  pcheck 'claude --agent evaluator ".".' '{"agent":"evaluator","command":"claude --agent evaluator \".\" --name \"evaluator: repo (opus)\"","run":"S evaluator ."}'
}

# old: parse: sessions: straight open quote, curly close
@test "/run-agent sessions: straight open quote, curly close" {
  pcheck 'claude --agent evaluator "I’m on my phone”' "{$EVP}"
}

# old: parse: sessions: planner prompt, straight open, curly close
@test "/run-agent sessions: planner prompt, straight open, curly close" {
  pcheck 'claude --agent planner "Replan based on plans/EVAL.md”' '{"agent":"planner","prompt":"Replan based on plans/EVAL.md","command":"claude --agent planner \"Replan based on plans/EVAL.md\" --name \"planner: repo (fable)\"","run":"S planner '"'"'Replan based on plans/EVAL.md'"'"'"}'
}

# old: parse: sessions: confirm before the curly prompt
@test "/run-agent sessions: confirm before the curly prompt" {
  pcheck 'evaluator confirm “I’m on my phone”' "{$EVP,\"confirm\":1}"
}

# old: parse: sessions: confirm after the curly prompt
@test "/run-agent sessions: confirm after the curly prompt" {
  pcheck 'evaluator “I’m on my phone” confirm' "{$EVP,\"confirm\":1}"
}

# old: parse: sessions: --confirm flag
@test "/run-agent sessions: --confirm flag" {
  pcheck 'evaluator “I’m on my phone” --confirm' "{$EVP,\"confirm\":1}"
}

# old: parse: sessions: newline inside a curly prompt
@test "/run-agent sessions: newline inside a curly prompt" {
  pcheck 'evaluator “I’m on my
Phone”' '{"agent":"evaluator","prompt":"I’m on my\nPhone","command":"claude --agent evaluator \"I’m on my\nPhone\" --name \"evaluator: repo (opus)\"","run":"S evaluator '"'"'I’m on my\nPhone'"'"'"}'
}

# old: parse: sessions: 'model fable, effort medium' words
@test "/run-agent sessions: 'model fable, effort medium' words" {
  pcheck 'worker, model fable, effort medium' "{$FL}"
}

# old: parse: sessions: model=opus, effort=medium
@test "/run-agent sessions: model=opus, effort=medium" {
  pcheck 'worker model=opus, effort=medium' '{"flags":"--model opus --effort medium","command":"claude --agent worker \".\" --model opus --effort medium --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --effort medium"}'
}

# old: parse: sessions: 'using opus'
@test "/run-agent sessions: 'using opus'" {
  pcheck 'worker "." using opus' '{"flags":"--model opus","command":"claude --agent worker \".\" --model opus --name \"worker: repo (opus)\"","run":"S worker . -- --model opus"}'
}

# old: parse: sessions: flag before the agent
@test "/run-agent sessions: flag before the agent" {
  pcheck '--model opus worker "."' '{"flags":"--model opus","command":"claude --agent worker \".\" --model opus --name \"worker: repo (opus)\"","run":"S worker . -- --model opus"}'
}

# old: parse: sessions: stray words -> unsure
@test "/run-agent sessions: stray words -> unsure" {
  pcheck 'worker . extra words' '{"unsure":["extra","words"]}'
}

# old: parse: sessions: yolo
@test "/run-agent sessions: yolo" {
  pcheck 'worker yolo' '{"flags":"--dangerously-skip-permissions","command":"claude --agent worker \".\" --dangerously-skip-permissions --name \"worker: repo (sonnet)\"","run":"S worker . -- --dangerously-skip-permissions"}'
}

# old: parse: sessions: bare agent 'planner' (no default prompt)
@test "/run-agent sessions: bare agent 'planner' (no default prompt)" {
  pcheck 'planner' '{"agent":"planner","prompt":"","command":"claude --agent planner --name \"planner: repo (fable)\"","run":"S planner"}'
}

# old: parse: typo: fabel -> fable
@test "/run-agent typo: fabel -> fable" {
  pcheck 'worker fabel low' "{$FLOW,\"corrections\":[\"fabel -> fable\"]}"
}

# old: parse: typo: efort lo -> effort low
@test "/run-agent typo: efort lo -> effort low" {
  pcheck 'worker efort lo' '{"flags":"--effort low","corrections":["efort -> effort","lo -> low"],"command":"claude --agent worker \".\" --effort low --name \"worker: repo (sonnet)\"","run":"S worker . -- --effort low"}'
}

# old: parse: typo: wroker -> worker
@test "/run-agent typo: wroker -> worker" {
  pcheck 'wroker fable' '{"flags":"--model fable","corrections":["wroker -> worker"],"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}'
}

# old: parse: typo: zzqx -> unsure
@test "/run-agent typo: zzqx -> unsure" {
  pcheck 'worker zzqx' '{"unsure":["zzqx"]}'
}

# old: parse: typo: lwo (tie low/two-ish) -> unsure
@test "/run-agent typo: lwo (tie low/two-ish) -> unsure" {
  pcheck 'worker fable lwo' '{"flags":"--model fable","unsure":["lwo"],"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}'
}

# old: parse: words: with opus yolo resume
@test "/run-agent words: with opus yolo resume" {
  pcheck 'worker with opus yolo resume' '{"flags":"--model opus --dangerously-skip-permissions --continue","command":"claude --agent worker \".\" --model opus --dangerously-skip-permissions --continue --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --dangerously-skip-permissions --continue"}'
}

# old: parse: words: just do it is three unplaceable words
@test "/run-agent words: just do it is three unplaceable words" {
  pcheck 'worker just do it' '{"unsure":["just","do","it"]}'
}

# old: parse: words: confirm inside the prompt is prompt
@test "/run-agent words: confirm inside the prompt is prompt" {
  pcheck 'worker "confirm"' '{"prompt":"confirm","command":"claude --agent worker \"confirm\" --name \"worker: repo (sonnet)\"","run":"S worker confirm"}'
}

# old: parse: words: old force words inside the prompt are prompt
@test "/run-agent words: old force words inside the prompt are prompt" {
  pcheck 'worker "go now"' '{"prompt":"go now","command":"claude --agent worker \"go now\" --name \"worker: repo (sonnet)\"","run":"S worker '"'"'go now'"'"'"}'
}

# old: parse: words: worker! -> the bare ! is unplaceable
@test "/run-agent words: worker! -> the bare ! is unplaceable" {
  pcheck 'worker! fable' '{"flags":"--model fable","unsure":["!"],"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}'
}

# old: parse: words: trailing ! is unplaceable
@test "/run-agent words: trailing ! is unplaceable" {
  pcheck 'worker "." !' '{"unsure":["!"]}'
}

# old: parse: words: force alone is unplaceable
@test "/run-agent words: force alone is unplaceable" {
  pcheck 'worker force' '{"unsure":["force"]}'
}

# old: parse: words: go alone is unplaceable
@test "/run-agent words: go alone is unplaceable" {
  pcheck 'worker go' '{"unsure":["go"]}'
}

# old: parse: words: yolo-run is unplaceable
@test "/run-agent words: yolo-run is unplaceable" {
  pcheck 'worker yolo-run' '{"unsure":["yolo-run"]}'
}

# old: parse: words: no confirm = two unplaceable words
@test "/run-agent words: no confirm = two unplaceable words" {
  pcheck 'worker no confirm' '{"unsure":["no","confirm"]}'
}

# old: parse: words: now = at once, no schedule
@test "/run-agent words: now = at once, no schedule" {
  pcheck 'worker now' '{}'
}

# old: parse: words: confirm = confirm:1
@test "/run-agent words: confirm = confirm:1" {
  pcheck 'worker "." confirm' '{"confirm":1}'
}

# old: parse: words: --confirm = confirm:1
@test "/run-agent words: --confirm = confirm:1" {
  pcheck 'worker --confirm' '{"confirm":1}'
}

# old: parse: words: --force / -f fall where unknown flags fall
@test "/run-agent words: --force / -f fall where unknown flags fall" {
  pcheck 'worker --force -f' '{"flags":"--force -f","command":"claude --agent worker \".\" --force -f --name \"worker: repo (sonnet)\"","run":"S worker . -- --force -f"}'
}

# old: words: --parse has no force key
@test "/run-agent words: --parse has no force key" {
  run ra --parse 'worker "." confirm'
  assert_success
  assert_output --partial '"confirm"'
  refute_output --partial '"force"'
}

# old: parse: words: ~ path token
@test "/run-agent words: a path under the home folder" {
  load ../fixtures/run-agent/tilde
  pcheck "$TILDE_FILES" "$(printf '%s' "$TILDE_FILES_WANT" | sed 's/"exists"/"missing"/')"
  mkdir "$TEST_HOME/files"
  pcheck "$TILDE_FILES" "$TILDE_FILES_WANT"
}

# old: parse: words: --name given
@test "/run-agent words: --name given" {
  pcheck 'worker --name mine' '{"flags":"--name mine","command":"claude --agent worker \".\" --name \"mine\"","run":"S worker . -- --name mine"}'
}

# old: parse: words: two directories -> error
@test "/run-agent words: two directories -> error" {
  load ../fixtures/run-agent/tilde
  pcheck "$TILDE_TWO" "$TILDE_TWO_WANT"
}

# old: parse: words: planner has no default prompt
@test "/run-agent words: planner has no default prompt" {
  pcheck 'planner opus' '{"agent":"planner","prompt":"","flags":"--model opus","command":"claude --agent planner --model opus --name \"planner: repo (opus)\"","run":"S planner -- --model opus"}'
}
