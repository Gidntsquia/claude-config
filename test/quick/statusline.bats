#!/usr/bin/env bats
# statusline.sh: the line Claude Code draws, from the JSON it pipes in.

load ../helpers/common

setup() {
  temp_home
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  P="$BATS_TEST_TMPDIR/my-project"
  mkdir -p "$P"
  unset CLAUDE_STATUSLINE_THEME CLAUDE_STATUSLINE_NF
}

# line [extra JSON members]: draw the bar for project $P, colour codes removed.
line() {
  local json
  json="{\"workspace\":{\"current_dir\":\"$P\",\"project_dir\":\"$P\"},\"model\":{\"display_name\":\"${MODEL:-Sonnet 5}\"}${1:+,$1}}"
  printf '%s' "$json" | bash "$REPO/statusline.sh" > "$TMPDIR/raw"
  RAW="$(cat "$TMPDIR/raw")"
  output="$(sed $'s/\033\\[[0-9;]*m//g' "$TMPDIR/raw")"
}

limits() { printf '"rate_limits":{"five_hour":{"used_percentage":%s},"seven_day":{"used_percentage":%s}}' "$1" "$2"; }

# bats test_tags=feature:statusline
@test "statusline: it shows the project folder and the model, dropping a default version number" {
  line
  assert_output --partial "my-project |"
  assert_output --partial "| Sonnet |"
  refute_output --partial "Sonnet 5"
  MODEL="Sonnet 5.5" line
  assert_output --partial "| Sonnet 5.5 |"
}

# bats test_tags=feature:statusline
@test "statusline: the reasoning effort is drawn as a gauge beside the model" {
  line '"effort":{"level":"high"}'
  assert_output --partial "| Sonnet ◑ |"
}

# bats test_tags=feature:statusline
@test "statusline: in a git folder it shows the branch, cut short past 20 characters" {
  git -C "$P" init -q
  git -C "$P" symbolic-ref HEAD refs/heads/short-one
  line
  assert_output --partial "| short-one |"
  git -C "$P" symbolic-ref HEAD refs/heads/a-very-long-branch-name-indeed
  line
  assert_output --partial "| a-very-long-branch-… |"
}

# bats test_tags=feature:statusline
@test "statusline: the 5 hour usage always shows, the weekly figure only from 70 percent" {
  line "$(limits 12 69)"
  assert_output --partial "| 5h 12% |"
  refute_output --partial "7d"
  line "$(limits 12 70)"
  assert_output --partial "| 5h 12% 7d 70% |"
}

# bats test_tags=feature:statusline
@test "statusline: usage turns red at 90 percent and not before" {
  line "$(limits 89 10)"
  case "$RAW" in *"48;2;204;36;29"*) return 1 ;; esac
  line "$(limits 90 10)"
  case "$RAW" in *"48;2;204;36;29"*) ;; *) return 1 ;; esac
}

# bats test_tags=feature:statusline
@test "statusline: before the first reply it shows the last usage it saw" {
  line "$(limits 33 75)"
  line
  assert_output --partial "| 5h 33% 7d 75% |"
}

# bats test_tags=feature:statusline
@test "statusline: --preview lists 25 easter eggs for each theme and rejects another name" {
  run bash "$REPO/statusline.sh" --preview
  assert_success
  assert_equal "$(printf '%s\n' "$output" | grep -c '^squid ')" 25
  assert_equal "$(printf '%s\n' "$output" | grep -c '^plane ')" 25
  run bash "$REPO/statusline.sh" --preview whale
  assert_failure 1
  assert_output "usage: statusline.sh --preview [squid|plane]"
}

# bats test_tags=feature:statusline
@test "statusline: an ordinary session shows the plain mascot of its theme" {
  # session id "s1" rolls above every easter egg band
  roll="$(printf '%s' s1 | cksum | awk '{print $1 % 10000}')"
  [ "$roll" -ge 1245 ]
  line '"session_id":"s1"'
  assert_output --partial "🦑 my-project"
  CLAUDE_STATUSLINE_THEME=Plane line '"session_id":"s1"'
  assert_output --partial "✈️ my-project"
}
