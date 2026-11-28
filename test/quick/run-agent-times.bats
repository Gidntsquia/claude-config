#!/usr/bin/env bats
# The time phrases /run-agent understands.
# The whole JSON answer of --parse is compared, under a frozen clock (2026-10-22 6:00 PM ET) and a fake usage API.
# A case is one line; a line starting with # is a note on the case below it. Two forms:
#   pcases   <what is typed> => <the fields that differ from a bare worker launch>
#   tcases   <what is typed> => <when it runs, ET> | <the phrase kept> [| <how it was worked out> [| <other fields>]]
# Add a case by adding a line to the list of the behaviour it belongs to.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_clock; }
teardown() { ra_teardown; }

# bats file_tags=feature:run-agent
AT9='"at":1792717200,"at_text":"at 9pm","at_shown":"9:00 PM ET (at 9pm, in 3h 0m)","run":"S worker . --at 1792717200 --at-text '"'"'at 9pm'"'"'"'
RESETW='"reset":1792714801,"reset_shown":"8:20 PM ET"'
WIN='"at":1792714801,"at_shown":"8:20 PM ET (%s, in 2h 20m)","at_text":"%s","run":"S worker . --at 1792714801 --at-text %s --window"'

@test "/run-agent time: a clock time after at is its next occurrence" {
  pcases <<EOF
worker at 9pm => {$AT9,$RESET}
worker --at 9pm => {$AT9,$RESET}
worker at 9:30pm => {"at":1792719000,"at_text":"at 9:30pm","at_shown":"9:30 PM ET (at 9:30pm, in 3h 30m)","run":"S worker . --at 1792719000 --at-text 'at 9:30pm'",$RESET}
worker at 21:40 => {"at":1792719600,"at_text":"at 21:40","at_shown":"9:40 PM ET (at 21:40, in 3h 40m)","run":"S worker . --at 1792719600 --at-text 'at 21:40'",$RESET}
worker at 2140 => {"at":1792719600,"at_text":"at 2140","at_shown":"9:40 PM ET (at 2140, in 3h 40m)","run":"S worker . --at 1792719600 --at-text 'at 2140'",$RESET}
# at 9 (bare hour, next occurrence = 9 PM)
worker at 9 => {"at":1792717200,"at_text":"at 9","at_shown":"9:00 PM ET (at 9, in 3h 0m)","run":"S worker . --at 1792717200 --at-text 'at 9'",$RESET}
# at 5 (bare hour, 5 PM passed -> 5 AM)
worker at 5 => {"at":1792746000,"at_text":"at 5","at_shown":"5:00 AM ET (at 5, in 11h 0m)","run":"S worker . --at 1792746000 --at-text 'at 5'",$RESET}
# at 5 pm (passed -> tomorrow)
worker at 5 pm => {"at":1792789200,"at_text":"at 5 pm","at_shown":"5:00 PM ET (at 5 pm, in 23h 0m)","run":"S worker . --at 1792789200 --at-text 'at 5 pm'",$RESET}
EOF
}

@test "/run-agent time: a length of time after in counts from now" {
  pcases <<EOF
worker in 2h => {"at":1792713600,"at_text":"in 2h","at_shown":"8:00 PM ET (in 2h, in 2h 0m)","run":"S worker . --at 1792713600 --at-text 'in 2h'",$RESET}
worker --in 2h => {"at":1792713600,"at_text":"in 2h","at_shown":"8:00 PM ET (in 2h, in 2h 0m)","run":"S worker . --at 1792713600 --at-text 'in 2h'",$RESET}
worker in 90m => {"at":1792711800,"at_text":"in 90m","at_shown":"7:30 PM ET (in 90m, in 1h 30m)","run":"S worker . --at 1792711800 --at-text 'in 90m'",$RESET}
worker in 1h30 => {"at":1792711800,"at_text":"in 1h30","at_shown":"7:30 PM ET (in 1h30, in 1h 30m)","run":"S worker . --at 1792711800 --at-text 'in 1h30'",$RESET}
worker in 2 hours => {"at":1792713600,"at_text":"in 2 hours","at_shown":"8:00 PM ET (in 2 hours, in 2h 0m)","run":"S worker . --at 1792713600 --at-text 'in 2 hours'",$RESET}
worker in 45 min => {"at":1792709100,"at_text":"in 45 min","at_shown":"6:45 PM ET (in 45 min, in 45m)","run":"S worker . --at 1792709100 --at-text 'in 45 min'",$RESET}
EOF
  tcases <<EOF
worker in 2 hours 10 min => 2026-10-22 20:10 | in 2 hours 10 min | 
worker in an hour => 2026-10-22 19:00 | in an hour | 
EOF
}

@test "/run-agent time: a window phrase means the reset, and until bounds it" {
  pcases <<EOF
worker after window => {$(printf "$WIN" 'after window' 'after window' "'after window'"),$RESETW}
worker after the window => {$(printf "$WIN" 'after the window' 'after the window' "'after the window'"),$RESETW}
worker next window => {$(printf "$WIN" 'next window' 'next window' "'next window'"),$RESETW}
worker when the window resets => {$(printf "$WIN" 'when the window resets' 'when the window resets' "'when the window resets'"),$RESETW}
worker after reset => {$(printf "$WIN" 'after reset' 'after reset' "'after reset'"),$RESETW}
worker --after window => {$(printf "$WIN" 'after window' 'after window' "'after window'"),$RESETW}
worker after window until 11pm => {$(printf "$WIN" 'after window' 'after window' "'after window'"),$RESETW,"until":1792724400,"until_shown":"11:00 PM ET","until_text":"until 11pm","run":"S worker . --at 1792714801 --at-text 'after window' --window --until 1792724400"}
EOF
}

@test "/run-agent time: a length before or after the window or a clock time counts from that point" {
  tcases <<EOF
# 'two hours before the window' counts back from the reset
worker fable low two hours before the window => $(( 1792714800 - 7200 )) | two hours before the window | two hours before window 8:20 PM | {$FLJ}
# '1 hr before the current window' counts back from the reset
worker "." 1 hr before the current window => $(( 1792714800 - 3600 )) | 1 hr before the current window | 1 hr before window 8:20 PM
# '2 h after the window resets' counts on from the reset
worker 2 h after the window resets => $(( 1792714800 + 7200 )) | 2 h after the window resets | 2 h after window 8:20 PM
# '30 min before window ends' counts back from the reset
worker 30 min before window ends => $(( 1792714800 - 1800 )) | 30 min before window ends | 30 min before window 8:20 PM
worker 1 hr before 9pm => 2026-10-22 20:00 | 1 hr before 9pm | 1 hr before 9:00 PM
worker 2 hours after 9pm => 2026-10-22 23:00 | 2 hours after 9pm | 2 hours after 9:00 PM
EOF
}

@test "/run-agent time: day words (tomorrow, tonight, today, noon, midnight, a weekday) pick the day and a default hour" {
  tcases <<EOF
# 'tomorrow at 1am' with a model and effort is the next calendar day
worker fable low tomorrow at 1am => 2026-10-23 01:00 | tomorrow at 1am |  | {$FLJ}
# tomorrow (default 9 AM)
worker tomorrow => 2026-10-23 09:00 | tomorrow | tomorrow, default 9:00 AM
worker tomorrow 7am => 2026-10-23 07:00 | tomorrow 7am | 
worker at 1am tomorrow => 2026-10-23 01:00 | at 1am tomorrow | 
worker 3pm tomorrow => 2026-10-23 15:00 | 3pm tomorrow | 
# tonight (default 7 PM)
worker tonight => 2026-10-22 19:00 | tonight | tonight, default 7:00 PM
# tonight at 9 (PM)
worker tonight at 9 => 2026-10-22 21:00 | tonight at 9 | 
# this evening (default 7 PM)
worker this evening => 2026-10-22 19:00 | this evening | this evening, default 7:00 PM
worker today at 9pm => 2026-10-22 21:00 | today at 9pm | 
# noon (next = tomorrow)
worker noon => 2026-10-23 12:00 | noon | 
worker at midnight => 2026-10-23 00:00 | at midnight | 
# friday at 3pm (tomorrow is Friday)
worker friday at 3pm => 2026-10-23 15:00 | friday at 3pm | 
# monday (next Monday, default 9 AM)
worker monday => 2026-10-26 09:00 | monday | monday, default 9:00 AM
# next thursday = a week ahead
worker next thursday 8am => 2026-10-29 08:00 | next thursday 8am | 
EOF
}

@test "/run-agent time: a time that cannot be read, or is already past, is asked about and schedules nothing" {
  pcases <<EOF
# until without a window phrase -> unsure
worker at 9pm until 11pm => {$AT9,$RESET,"unsure":["until 11pm"]}
# unparseable after at -> unsure
worker at 25pm => {"unsure":["at 25pm"]}
# today alone -> unsure
worker today => {"unsure":["today"]}
# tomorrow at 25pm -> unsure
worker tomorrow at 25pm => {"unsure":["tomorrow at 25pm"]}
# today at 5pm (already past) -> unsure
worker today at 5pm => {"unsure":["today at 5pm (already past)"]}
# 3 hours before the window (already past) -> at_error
worker 3 hours before the window => {"at_text":"3 hours before the window","at_error":"3 hours before the window = 5:20 PM ET, already past (window resets 8:20 PM ET)",$RESET}
EOF
}

@test "/run-agent time: a folder after in and a dry run keep their meaning beside a time" {
  pcases <<EOF
# in <dir> still a directory
worker in sibling => {"dir":"$T/sibling","dir_state":"exists","dir_typed":"sibling","command":"claude --agent worker \".\" --name \"worker: sibling (sonnet)\"","run":"S worker . --cwd $T/sibling"}
# dir + at 9pm
worker in ../../sibling at 9pm => {"dir":"$T/sibling","dir_state":"exists","dir_typed":"../../sibling","command":"claude --agent worker \".\" --name \"worker: sibling (sonnet)\"","at":1792717200,"at_text":"at 9pm","at_shown":"9:00 PM ET (at 9pm, in 3h 0m)",$RESET,"run":"S worker . --cwd $T/sibling --at 1792717200 --at-text 'at 9pm'"}
# dry with model, effort, at
worker fable low effort at 9pm dry => {$FLOW,"dry":1,"at":1792717200,"at_text":"at 9pm","at_shown":"9:00 PM ET (at 9pm, in 3h 0m)",$RESET,"run":"S worker . --at 1792717200 --at-text 'at 9pm' -- --model fable --effort low"}
worker dry run => {"dry":1,$RESET}
worker --dry-run => {"dry":1,$RESET}
EOF
}
