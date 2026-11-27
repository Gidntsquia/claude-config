#!/usr/bin/env bats
# The time phrases /run-agent understands.
# Each --parse test compares the whole JSON answer: a frozen clock (2026-10-22 6:00 PM ET), a fake usage API.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_clock; }
teardown() { ra_teardown; }

# bats file_tags=feature:run-agent
AT9='"at":1792717200,"at_text":"at 9pm","at_shown":"9:00 PM ET (at 9pm, in 3h 0m)","run":"S worker . --at 1792717200 --at-text '"'"'at 9pm'"'"'"'
RESETW='"reset":1792714801,"reset_shown":"8:20 PM ET"'
WIN='"at":1792714801,"at_shown":"8:20 PM ET (%s, in 2h 20m)","at_text":"%s","run":"S worker . --at 1792714801 --at-text %s --window"'

@test "/run-agent time: at 9pm and --at 9pm" {
  pcheck 'worker at 9pm' "{$AT9,$RESET}"
  pcheck 'worker --at 9pm' "{$AT9,$RESET}"
}

# old: parse: time: at 9:30pm
@test "/run-agent time: at 9:30pm" {
  pcheck 'worker at 9:30pm' "{\"at\":1792719000,\"at_text\":\"at 9:30pm\",\"at_shown\":\"9:30 PM ET (at 9:30pm, in 3h 30m)\",\"run\":\"S worker . --at 1792719000 --at-text 'at 9:30pm'\",$RESET}"
}

# old: parse: time: at 21:40
@test "/run-agent time: at 21:40" {
  pcheck 'worker at 21:40' "{\"at\":1792719600,\"at_text\":\"at 21:40\",\"at_shown\":\"9:40 PM ET (at 21:40, in 3h 40m)\",\"run\":\"S worker . --at 1792719600 --at-text 'at 21:40'\",$RESET}"
}

# old: parse: time: at 2140
@test "/run-agent time: at 2140" {
  pcheck 'worker at 2140' "{\"at\":1792719600,\"at_text\":\"at 2140\",\"at_shown\":\"9:40 PM ET (at 2140, in 3h 40m)\",\"run\":\"S worker . --at 1792719600 --at-text 'at 2140'\",$RESET}"
}

# old: parse: time: at 9 (bare hour, next occurrence = 9 PM)
@test "/run-agent time: at 9 (bare hour, next occurrence = 9 PM)" {
  pcheck 'worker at 9' "{\"at\":1792717200,\"at_text\":\"at 9\",\"at_shown\":\"9:00 PM ET (at 9, in 3h 0m)\",\"run\":\"S worker . --at 1792717200 --at-text 'at 9'\",$RESET}"
}

# old: parse: time: at 5 (bare hour, 5 PM passed -> 5 AM)
@test "/run-agent time: at 5 (bare hour, 5 PM passed -> 5 AM)" {
  pcheck 'worker at 5' "{\"at\":1792746000,\"at_text\":\"at 5\",\"at_shown\":\"5:00 AM ET (at 5, in 11h 0m)\",\"run\":\"S worker . --at 1792746000 --at-text 'at 5'\",$RESET}"
}

# old: parse: time: at 5 pm (passed -> tomorrow)
@test "/run-agent time: at 5 pm (passed -> tomorrow)" {
  pcheck 'worker at 5 pm' "{\"at\":1792789200,\"at_text\":\"at 5 pm\",\"at_shown\":\"5:00 PM ET (at 5 pm, in 23h 0m)\",\"run\":\"S worker . --at 1792789200 --at-text 'at 5 pm'\",$RESET}"
}

@test "/run-agent time: in 2h and --in 2h" {
  pcheck 'worker in 2h' "{\"at\":1792713600,\"at_text\":\"in 2h\",\"at_shown\":\"8:00 PM ET (in 2h, in 2h 0m)\",\"run\":\"S worker . --at 1792713600 --at-text 'in 2h'\",$RESET}"
  pcheck 'worker --in 2h' "{\"at\":1792713600,\"at_text\":\"in 2h\",\"at_shown\":\"8:00 PM ET (in 2h, in 2h 0m)\",\"run\":\"S worker . --at 1792713600 --at-text 'in 2h'\",$RESET}"
}

# old: parse: time: in 90m
@test "/run-agent time: in 90m" {
  pcheck 'worker in 90m' "{\"at\":1792711800,\"at_text\":\"in 90m\",\"at_shown\":\"7:30 PM ET (in 90m, in 1h 30m)\",\"run\":\"S worker . --at 1792711800 --at-text 'in 90m'\",$RESET}"
}

# old: parse: time: in 1h30
@test "/run-agent time: in 1h30" {
  pcheck 'worker in 1h30' "{\"at\":1792711800,\"at_text\":\"in 1h30\",\"at_shown\":\"7:30 PM ET (in 1h30, in 1h 30m)\",\"run\":\"S worker . --at 1792711800 --at-text 'in 1h30'\",$RESET}"
}

# old: parse: time: in 2 hours
@test "/run-agent time: in 2 hours" {
  pcheck 'worker in 2 hours' "{\"at\":1792713600,\"at_text\":\"in 2 hours\",\"at_shown\":\"8:00 PM ET (in 2 hours, in 2h 0m)\",\"run\":\"S worker . --at 1792713600 --at-text 'in 2 hours'\",$RESET}"
}

# old: parse: time: in 45 min
@test "/run-agent time: in 45 min" {
  pcheck 'worker in 45 min' "{\"at\":1792709100,\"at_text\":\"in 45 min\",\"at_shown\":\"6:45 PM ET (in 45 min, in 45m)\",\"run\":\"S worker . --at 1792709100 --at-text 'in 45 min'\",$RESET}"
}

@test "/run-agent time: after window, after the window, next window, when the window resets, after reset and --after window all mean the reset" {
  local p
  for p in 'after window' 'after the window' 'next window' 'when the window resets' 'after reset'; do
    pcheck "worker $p" "{$(printf "$WIN" "$p" "$p" "'$p'"),$RESETW}"
  done
  pcheck 'worker --after window' "{$(printf "$WIN" 'after window' 'after window' "'after window'"),$RESETW}"
}

# old: parse: time: after window until 11pm
@test "/run-agent time: after window until 11pm" {
  pcheck 'worker after window until 11pm' "{$(printf "$WIN" 'after window' 'after window' "'after window'"),$RESETW,\"until\":1792724400,\"until_shown\":\"11:00 PM ET\",\"until_text\":\"until 11pm\",\"run\":\"S worker . --at 1792714801 --at-text 'after window' --window --until 1792724400\"}"
}

# old: parse: time: until without a window phrase -> unsure
@test "/run-agent time: until without a window phrase -> unsure" {
  pcheck 'worker at 9pm until 11pm' "{$AT9,$RESET,\"unsure\":[\"until 11pm\"]}"
}

# old: parse: time: unparseable after at -> unsure
@test "/run-agent time: unparseable after at -> unsure" {
  pcheck 'worker at 25pm' '{"unsure":["at 25pm"]}'
}

# old: parse: time: in <dir> still a directory
@test "/run-agent time: in <dir> still a directory" {
  pcheck 'worker in sibling' "{\"dir\":\"$T/sibling\",\"dir_state\":\"exists\",\"dir_typed\":\"sibling\",\"command\":\"claude --agent worker \\\".\\\" --name \\\"worker: sibling (sonnet)\\\"\",\"run\":\"S worker . --cwd $T/sibling\"}"
}

# old: parse: time: dir + at 9pm
@test "/run-agent time: dir + at 9pm" {
  pcheck 'worker in ../../sibling at 9pm' "{\"dir\":\"$T/sibling\",\"dir_state\":\"exists\",\"dir_typed\":\"../../sibling\",\"command\":\"claude --agent worker \\\".\\\" --name \\\"worker: sibling (sonnet)\\\"\",\"at\":1792717200,\"at_text\":\"at 9pm\",\"at_shown\":\"9:00 PM ET (at 9pm, in 3h 0m)\",$RESET,\"run\":\"S worker . --cwd $T/sibling --at 1792717200 --at-text 'at 9pm'\"}"
}

# old: parse: time: dry with model, effort, at
@test "/run-agent time: dry with model, effort, at" {
  pcheck 'worker fable low effort at 9pm dry' "{$FLOW,\"dry\":1,\"at\":1792717200,\"at_text\":\"at 9pm\",\"at_shown\":\"9:00 PM ET (at 9pm, in 3h 0m)\",$RESET,\"run\":\"S worker . --at 1792717200 --at-text 'at 9pm' -- --model fable --effort low\"}"
}

@test "/run-agent time: dry run and --dry-run alone fetch the reset" {
  pcheck 'worker dry run' "{\"dry\":1,$RESET}"
  pcheck 'worker --dry-run' "{\"dry\":1,$RESET}"
}

# old: parse: time: session 'tomorrow at 1am' (next calendar day)
@test "/run-agent time: 'tomorrow at 1am' with a model and effort is the next calendar day" {
  tcheck 'worker fable low tomorrow at 1am' "$(ep '2026-10-23 01:00')" 'tomorrow at 1am' '' "{$FLJ}"
}

# old: parse: time: session 'two hours before the window'
@test "/run-agent time: 'two hours before the window' counts back from the reset" {
  tcheck 'worker fable low two hours before the window' $(( 1792714800 - 7200 )) 'two hours before the window' 'two hours before window 8:20 PM' "{$FLJ}"
}

# old: parse: time: session '1 hr before the current window'
@test "/run-agent time: '1 hr before the current window' counts back from the reset" {
  tcheck 'worker "." 1 hr before the current window' $(( 1792714800 - 3600 )) '1 hr before the current window' '1 hr before window 8:20 PM'
}

# old: parse: time: 2 h after the window resets
@test "/run-agent time: '2 h after the window resets' counts on from the reset" {
  tcheck 'worker 2 h after the window resets' $(( 1792714800 + 7200 )) '2 h after the window resets' '2 h after window 8:20 PM'
}

# old: parse: time: 30 min before window ends
@test "/run-agent time: '30 min before window ends' counts back from the reset" {
  tcheck 'worker 30 min before window ends' $(( 1792714800 - 1800 )) '30 min before window ends' '30 min before window 8:20 PM'
}

# old: parse: time: 1 hr before 9pm
@test "/run-agent time: 1 hr before 9pm" {
  tcheck 'worker 1 hr before 9pm' "$(ep '2026-10-22 20:00')" '1 hr before 9pm' '1 hr before 9:00 PM'
}

# old: parse: time: 2 hours after 9pm
@test "/run-agent time: 2 hours after 9pm" {
  tcheck 'worker 2 hours after 9pm' "$(ep '2026-10-22 23:00')" '2 hours after 9pm' '2 hours after 9:00 PM'
}

# old: parse: time: tomorrow (default 9 AM)
@test "/run-agent time: tomorrow (default 9 AM)" {
  tcheck 'worker tomorrow' "$(ep '2026-10-23 09:00')" 'tomorrow' 'tomorrow, default 9:00 AM'
}

# old: parse: time: tomorrow 7am
@test "/run-agent time: tomorrow 7am" {
  tcheck 'worker tomorrow 7am' "$(ep '2026-10-23 07:00')" 'tomorrow 7am' ''
}

# old: parse: time: at 1am tomorrow
@test "/run-agent time: at 1am tomorrow" {
  tcheck 'worker at 1am tomorrow' "$(ep '2026-10-23 01:00')" 'at 1am tomorrow' ''
}

# old: parse: time: 3pm tomorrow
@test "/run-agent time: 3pm tomorrow" {
  tcheck 'worker 3pm tomorrow' "$(ep '2026-10-23 15:00')" '3pm tomorrow' ''
}

# old: parse: time: tonight (default 7 PM)
@test "/run-agent time: tonight (default 7 PM)" {
  tcheck 'worker tonight' "$(ep '2026-10-22 19:00')" 'tonight' 'tonight, default 7:00 PM'
}

# old: parse: time: tonight at 9 (PM)
@test "/run-agent time: tonight at 9 (PM)" {
  tcheck 'worker tonight at 9' "$(ep '2026-10-22 21:00')" 'tonight at 9' ''
}

# old: parse: time: this evening (default 7 PM)
@test "/run-agent time: this evening (default 7 PM)" {
  tcheck 'worker this evening' "$(ep '2026-10-22 19:00')" 'this evening' 'this evening, default 7:00 PM'
}

# old: parse: time: today at 9pm
@test "/run-agent time: today at 9pm" {
  tcheck 'worker today at 9pm' "$(ep '2026-10-22 21:00')" 'today at 9pm' ''
}

# old: parse: time: noon (next = tomorrow)
@test "/run-agent time: noon (next = tomorrow)" {
  tcheck 'worker noon' "$(ep '2026-10-23 12:00')" 'noon' ''
}

# old: parse: time: at midnight
@test "/run-agent time: at midnight" {
  tcheck 'worker at midnight' "$(ep '2026-10-23 00:00')" 'at midnight' ''
}

# old: parse: time: friday at 3pm (tomorrow is Friday)
@test "/run-agent time: friday at 3pm (tomorrow is Friday)" {
  tcheck 'worker friday at 3pm' "$(ep '2026-10-23 15:00')" 'friday at 3pm' ''
}

# old: parse: time: monday (next Monday, default 9 AM)
@test "/run-agent time: monday (next Monday, default 9 AM)" {
  tcheck 'worker monday' "$(ep '2026-10-26 09:00')" 'monday' 'monday, default 9:00 AM'
}

# old: parse: time: next thursday = a week ahead
@test "/run-agent time: next thursday = a week ahead" {
  tcheck 'worker next thursday 8am' "$(ep '2026-10-29 08:00')" 'next thursday 8am' ''
}

# old: parse: time: in 2 hours 10 min
@test "/run-agent time: in 2 hours 10 min" {
  tcheck 'worker in 2 hours 10 min' "$(ep '2026-10-22 20:10')" 'in 2 hours 10 min' ''
}

# old: parse: time: in an hour
@test "/run-agent time: in an hour" {
  tcheck 'worker in an hour' "$(ep '2026-10-22 19:00')" 'in an hour' ''
}

# old: parse: time: today alone -> unsure
@test "/run-agent time: today alone -> unsure" {
  pcheck 'worker today' '{"unsure":["today"]}'
}

# old: parse: time: tomorrow at 25pm -> unsure
@test "/run-agent time: tomorrow at 25pm -> unsure" {
  pcheck 'worker tomorrow at 25pm' '{"unsure":["tomorrow at 25pm"]}'
}

# old: parse: time: today at 5pm (already past) -> unsure
@test "/run-agent time: today at 5pm (already past) -> unsure" {
  pcheck 'worker today at 5pm' '{"unsure":["today at 5pm (already past)"]}'
}

# old: parse: time: 3 hours before the window (already past) -> at_error
@test "/run-agent time: 3 hours before the window (already past) -> at_error" {
  pcheck 'worker 3 hours before the window' "{\"at_text\":\"3 hours before the window\",\"at_error\":\"3 hours before the window = 5:20 PM ET, already past (window resets 8:20 PM ET)\",$RESET}"
}
