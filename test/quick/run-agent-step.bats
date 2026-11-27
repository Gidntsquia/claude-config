# bats file_tags=feature:run-agent
# The confirm state machine (--step): the script applies the answers, the model only asks. Frozen clock
# 2026-10-22 6:00 PM ET; the window resets at 8:20 PM ET.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_clock; export RUN_AGENT_NO_RETRY=1; }
teardown() { ra_teardown; }

step() { run ra --step "$1"; }
scheduled() { has "$output" '^scheduled #[0-9]*: '; }
asks() { has "$output" "header \"$1\""; }
says() { grep -qF -- "$1" <<<"$output" || { echo "missing: $1"; echo "$output"; return 1; }; }
never() { no grep -qi -- "$1" <<<"$output"; }

# old: step: unsure word -> one question, answer appended after ' | ', no guessed reading
@test "an unclear word gets one question, with no guessed reading" {
  step 'worker zzqx confirm'
  says 'AskUserQuestion once: header "Unsure", question "I could not place `zzqx` in: worker zzqx confirm'
  says '"Part of the prompt", "Drop it"'
  says "--step 'worker zzqx confirm | '<the chosen option label or the typed text>"
  never 'best reading\|--effort'
}

# old: step: 'Drop it' -> the confirm question for the rest
@test "answering 'Drop it' moves on to the confirm question" {
  step 'worker zzqx confirm | Drop it'
  asks 'Run?'
  says 'Replace this session with: claude --agent worker "." --name "worker: repo (sonnet)"'
  says "--step 'worker confirm | '"
}

# old: step: 'Part of the prompt' -> word moved into the prompt
@test "answering 'Part of the prompt' puts the word in the prompt" {
  step 'worker zzqx confirm | Part of the prompt'
  says 'claude --agent worker "zzqx"'
}

# old: step: No -> nothing changed
@test "answering No changes nothing" {
  step 'worker zzqx confirm | Drop it | No'
  assert_output 'Reply exactly `nothing changed` and stop.'
}

# old: step: unsure word dropped, no confirm -> the script schedules at once
@test "without 'confirm', dropping the unclear word schedules at once" { step 'worker zzqx in 10m | Drop it'; scheduled; }

# old: step: three answers without a run -> nothing changed + type by hand
@test "after three unusable answers nothing changes and you are told to type it by hand" {
  step 'worker zzqx confirm | foo1 | foo2 | foo3'
  has "$output" '^nothing changed$'
  has "$output" '^type it by hand'
}

# old: step: no agent -> agent question
@test "with no agent named, the question is which agent" {
  step 'fable low'
  asks Agent
  says "--step 'fable low | '<the chosen agent name>"
}

# old: step: prompt only -> agent question, no usage line
@test "a prompt alone asks which agent instead of printing usage" {
  step '"fix it"'
  asks Agent
  no grep -q '^usage' <<<"$output"
}

# old: step: agent answer -> confirm
@test "the agent answer leads to the confirm question" {
  step 'fable low confirm | worker'
  asks 'Run?'
  says '--model fable --effort low'
}

# old: step: agent answer, no confirm -> scheduled at once
@test "without 'confirm', the agent answer schedules at once" { step 'fable low in 10m | worker'; scheduled; }

# old: step: session 'tomorrow at 1am' -> one Schedule? question
@test "'tomorrow at 1am' with confirm asks one Schedule? question" {
  step 'worker fable low tomorrow at 1am confirm'
  asks 'Schedule?'
  says 'at 1:00 AM ET (tomorrow at 1am, in 7h 0m)'
  no grep -q AskUserQuestion <<<"$(printf '%s\n' "$output" | sed 1d)"
}

# old: step: session 'two hours before the window' -> scheduled without confirm, no question | step: jobs names the derivation too
@test "'two hours before the window' schedules without a question, and --jobs shows how the time was worked out" {
  step 'worker fable low two hours before the window'
  has "$output" '^scheduled #[0-9]*: claude --agent worker "." --model fable --effort low --name "worker: repo (fable)" at 6:20 PM ET (two hours before window 8:20 PM, in 20m)$'
  never AskUserQuestion
  has "$(ra --jobs)" 'at 6:20 PM ET (two hours before window 8:20 PM, in 20m)  \[sleeping'
}

# old: step: unparsed time words -> haiku resolves, no question to the user
@test "time words the parser cannot read go to the model to resolve, with no question to you" {
  step 'worker fable low the day after tomorrow 3pm'
  has "$output" "^Resolve the time words \`the day after\` (and the parser's own reading \`tomorrow 3pm\`, which your answer replaces) in: worker fable low the day after tomorrow 3pm yourself"
  says "--step 'worker fable low the day after tomorrow 3pm | time: '<at <clock>|in <delay>>"
  never 'AskUserQuestion\|header "'
}

# old: step: haiku's time answer -> scheduled at once (no confirm typed)
@test "the resolved time schedules at once" {
  step 'worker fable low the day after tomorrow 3pm | time: in 45h'
  has "$output" '^scheduled #[0-9]*: .* at 3:00 PM ET (in 45h, in 45h 0m)$'
}

# old: step: 'time: in 45h' replaces the time words and the parser's reading -> Schedule? question
@test "with confirm, the resolved time replaces the old words in the Schedule? question" {
  step 'worker fable low confirm the day after tomorrow 3pm | time: in 45h'
  asks 'Schedule?'
  says 'at 3:00 PM ET (in 45h, in 45h 0m)'
  says "--step 'worker fable low confirm in 45h | '"
}

# old: step: Yes -> the script schedules (no command handed to haiku)
@test "answering Yes makes the script schedule the run itself" {
  unset RUN_AGENT_NOW
  step 'worker in 10m confirm | Yes'; scheduled
}

# old: step: answers after a run are not read
@test "answers after the run is scheduled are ignored" {
  unset RUN_AGENT_NOW
  step 'worker in 10m confirm | Yes | ignored'; scheduled
}

# old: step: no model typed -> 'model: sonnet (default; type fable/opus to change)' and (sonnet, default)
@test "with no model typed the confirm question names the default" {
  step 'worker 1 hour before the window confirm'
  says 'model: sonnet (default; type fable/opus to change)'
  says '(sonnet, default)'
}

# old: step: typed fable -> fable, no 'default'
@test "a typed model is shown as typed, not as a default" {
  step 'worker fable 1 hour before the window confirm'
  says '--model fable'
  never default
}
