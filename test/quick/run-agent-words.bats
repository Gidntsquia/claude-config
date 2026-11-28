#!/usr/bin/env bats
# What /run-agent understands from what people typed: flag spellings, quotes, pasted lines, typos, stray words.
# The whole JSON answer of --parse is compared, under a frozen clock (2026-10-22 6:00 PM ET) and a fake usage API.
# A case is one line, `<what is typed> => <the fields that differ from a bare worker launch>`; a line starting
# with # is a note on the case below it. Add a case by adding a line to the list of the behaviour it belongs to.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_clock; export RUN_AGENT_NO_RETRY=1; }
teardown() { ra_teardown; }

# bats file_tags=feature:run-agent
EVP='"agent":"evaluator","prompt":"I’m on my phone","command":"claude --agent evaluator \"I’m on my phone\" --name \"evaluator: repo (opus)\"","run":"S evaluator '"'"'I’m on my phone'"'"'"'

@test "/run-agent words: model, effort and other flags, however they are spelled, become the launch's flags" {
  pcases <<EOF
# key=value, spaced =, commas
worker, model=fable effort = medium, => {$FL}
worker model=fable effort =medium => {$FL}
# em dashes
worker —model fable —effort low => {$FLOW}
# single dashes
worker -model fable -effort low => {$FLOW}
# bare model + '<effort> effort'
worker fable low effort => {$FLOW}
# model+effort
worker, opus+medium effort => {"flags":"--model opus --effort medium","command":"claude --agent worker \".\" --model opus --effort medium --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --effort medium"}
# commas everywhere
worker, model=fable, effort=medium, => {$FL}
# haiku 'could not parse' bare model + em-dash effort
worker fable —effort low => {$FLOW}
# 'model fable, effort medium' words
worker, model fable, effort medium => {$FL}
worker model=opus, effort=medium => {"flags":"--model opus --effort medium","command":"claude --agent worker \".\" --model opus --effort medium --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --effort medium"}
worker "." using opus => {"flags":"--model opus","command":"claude --agent worker \".\" --model opus --name \"worker: repo (opus)\"","run":"S worker . -- --model opus"}
# flag before the agent
--model opus worker "." => {"flags":"--model opus","command":"claude --agent worker \".\" --model opus --name \"worker: repo (opus)\"","run":"S worker . -- --model opus"}
worker yolo => {"flags":"--dangerously-skip-permissions","command":"claude --agent worker \".\" --dangerously-skip-permissions --name \"worker: repo (sonnet)\"","run":"S worker . -- --dangerously-skip-permissions"}
worker with opus yolo resume => {"flags":"--model opus --dangerously-skip-permissions --continue","command":"claude --agent worker \".\" --model opus --dangerously-skip-permissions --continue --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --dangerously-skip-permissions --continue"}
# --force / -f fall where unknown flags fall
worker --force -f => {"flags":"--force -f","command":"claude --agent worker \".\" --force -f --name \"worker: repo (sonnet)\"","run":"S worker . -- --force -f"}
# --name given
worker --name mine => {"flags":"--name mine","command":"claude --agent worker \".\" --name \"mine\"","run":"S worker . -- --name mine"}
EOF
}

@test "/run-agent words: the prompt is what sits in quotes, straight or curly, with its line breaks; planner has no default prompt" {
  pcases <<EOF
# curly quotes
evaluator “I’m on my phone” => {"agent":"evaluator","prompt":"I’m on my phone","command":"claude --agent evaluator \"I’m on my phone\" --name \"evaluator: repo (opus)\"","run":"S evaluator 'I’m on my phone'"}
# newline inside the prompt
planner "line one\nline two" --model opus => {"agent":"planner","prompt":"line one\nline two","flags":"--model opus","command":"claude --agent planner \"line one\nline two\" --model opus --name \"planner: repo (opus)\"","run":"S planner 'line one\nline two' -- --model opus"}
# straight open quote, curly close
claude --agent evaluator "I’m on my phone” => {$EVP}
# planner prompt, straight open, curly close
claude --agent planner "Replan based on plans/EVAL.md” => {"agent":"planner","prompt":"Replan based on plans/EVAL.md","command":"claude --agent planner \"Replan based on plans/EVAL.md\" --name \"planner: repo (fable)\"","run":"S planner 'Replan based on plans/EVAL.md'"}
# newline inside a curly prompt
evaluator “I’m on my\nPhone” => {"agent":"evaluator","prompt":"I’m on my\nPhone","command":"claude --agent evaluator \"I’m on my\nPhone\" --name \"evaluator: repo (opus)\"","run":"S evaluator 'I’m on my\nPhone'"}
# confirm inside the prompt is prompt
worker "confirm" => {"prompt":"confirm","command":"claude --agent worker \"confirm\" --name \"worker: repo (sonnet)\"","run":"S worker confirm"}
# old force words inside the prompt are prompt
worker "go now" => {"prompt":"go now","command":"claude --agent worker \"go now\" --name \"worker: repo (sonnet)\"","run":"S worker 'go now'"}
# bare agent 'planner' (no default prompt)
planner => {"agent":"planner","prompt":"","command":"claude --agent planner --name \"planner: repo (fable)\"","run":"S planner"}
# planner has no default prompt
planner opus => {"agent":"planner","prompt":"","flags":"--model opus","command":"claude --agent planner --model opus --name \"planner: repo (opus)\"","run":"S planner -- --model opus"}
# now = at once, no schedule
worker now => {}
EOF
}

@test "/run-agent words: a pasted claude --agent line is read like the short form" {
  pcases <<EOF
# claude --agent evaluator '.'
claude --agent evaluator "." => {"agent":"evaluator","command":"claude --agent evaluator \".\" --name \"evaluator: repo (opus)\"","run":"S evaluator ."}
# full claude command with em-dash flags
claude --agent worker "." —model fable —effort medium => {$FL}
# full claude command, trailing dot
claude --agent evaluator ".". => {"agent":"evaluator","command":"claude --agent evaluator \".\" --name \"evaluator: repo (opus)\"","run":"S evaluator ."}
EOF
}

@test "/run-agent words: confirm, Confirm and --confirm, before or after the prompt, ask before the run" {
  pcases <<EOF
# key=value, spaced =, commas, confirm
worker, model=fable effort = medium, confirm => {$FL,"confirm":1}
# confirm before em-dash flags
worker confirm —model fable —effort medium => {$FL,"confirm":1}
# full claude command, capital Confirm
claude --agent evaluator "." Confirm => {"agent":"evaluator","confirm":1,"command":"claude --agent evaluator \".\" --name \"evaluator: repo (opus)\"","run":"S evaluator ."}
# confirm before the curly prompt
evaluator confirm “I’m on my phone” => {$EVP,"confirm":1}
# confirm after the curly prompt
evaluator “I’m on my phone” confirm => {$EVP,"confirm":1}
# --confirm flag
evaluator “I’m on my phone” --confirm => {$EVP,"confirm":1}
worker "." confirm => {"confirm":1}
worker --confirm => {"confirm":1}
EOF
}

@test "/run-agent words: a misspelt word is corrected when exactly one known word is close" {
  pcases <<EOF
# fabel -> fable
worker fabel low => {$FLOW,"corrections":["fabel -> fable"]}
# efort lo -> effort low
worker efort lo => {"flags":"--effort low","corrections":["efort -> effort","lo -> low"],"command":"claude --agent worker \".\" --effort low --name \"worker: repo (sonnet)\"","run":"S worker . -- --effort low"}
# wroker -> worker
wroker fable => {"flags":"--model fable","corrections":["wroker -> worker"],"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}
EOF
}

@test "/run-agent words: a word that cannot be placed is asked about, never guessed" {
  pcases <<EOF
# stray words -> unsure
worker . extra words => {"unsure":["extra","words"]}
# zzqx -> unsure
worker zzqx => {"unsure":["zzqx"]}
# lwo (tie low/two-ish) -> unsure
worker fable lwo => {"flags":"--model fable","unsure":["lwo"],"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}
worker just do it => {"unsure":["just","do","it"]}
worker "." ! => {"unsure":["!"]}
worker force => {"unsure":["force"]}
worker go => {"unsure":["go"]}
worker yolo-run => {"unsure":["yolo-run"]}
worker no confirm => {"unsure":["no","confirm"]}
# worker! -> the bare ! is unplaceable
worker! fable => {"flags":"--model fable","unsure":["!"],"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}
EOF
}

@test "/run-agent words: a path under the home folder" {
  load ../fixtures/run-agent/tilde
  pcheck "$TILDE_FILES" "$(printf '%s' "$TILDE_FILES_WANT" | sed 's/"exists"/"missing"/')"
  mkdir "$TEST_HOME/files"
  pcheck "$TILDE_FILES" "$TILDE_FILES_WANT"
}

@test "/run-agent words: two directories -> error" {
  load ../fixtures/run-agent/tilde
  pcheck "$TILDE_TWO" "$TILDE_TWO_WANT"
}
