# bats file_tags=feature:run-agent
# --handoff: stop at the usage limit with a note, a WIP commit and a scheduled relaunch.
load ../helpers/common
load ../helpers/run-agent

setup() {
  ra_setup; ra_tmux_setup
  H="$T/handoff"
  mkdir -p "$H"
  git -C "$H" init -q
  git -C "$H" commit -q --allow-empty -m init
  printf 'plans/\n' > "$H/.gitignore"
  echo a > "$H/a.txt"
  export TMUX="$(TM display -p '#{socket_path}'),0,0" TMUX_PANE="$(TM display -p -t t '#{pane_id}')"
  usage_at $(( $(date +%s) + 120 ))
}
teardown() { ra_teardown; }

# handoff <stdin text> <run-agent arguments...>: run it from the folder $H; sets status and output
handoff() {
  local in="$1"; shift
  printf '%b' "$in" > "$T/stdin"
  cd "$H" || return 1
  run ra --handoff "$@" < "$T/stdin"
}
NOT_IN_TMUX="Relaunch: not scheduled — not in tmux; run /run-agent worker after window to schedule it by hand"
full() { handoff 'Done: x\nIn progress: y\nNext: z\n' worker "." -- --model haiku; }

# old: handoff: prints Note / Commit / Relaunch
@test "handoff prints the note, the commit and the relaunch" {
  full
  assert_success
  assert_equal "$(line 1 "$output")" "Note: plans/WORKER_NOTES.md"
  has "$(line 2 "$output")" "^Commit: [0-9a-f]* WIP: stopped at usage limit — y\$"
  has "$(line 3 "$output")" "^Relaunch: .* ET (job #[0-9]*)\$"
}

# old: handoff: note section (heading with time, stdin, Uncommitted, Relaunch)
@test "the handoff note has a timed heading, the text given, the dirty files and the relaunch" {
  full
  local n; n="$(tail -n 6 "$H/plans/WORKER_NOTES.md")"
  has "$(line 1 "$n")" "^## Stopped at usage limit — 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9]*:[0-9][0-9] [AP]M ET\$"
  assert_equal "$(printf '%s\n' "$n" | sed -n 2,4p)" "$(printf 'Done: x\nIn progress: y\nNext: z')"
  assert_equal "$(line 5 "$n")" "Uncommitted/dirty: .gitignore, a.txt"
  has "$(line 6 "$n")" "^Relaunch: .* ET (job #[0-9]*)\$"
}

# old: handoff: WIP commit, tree clean, plans/ not committed
@test "handoff commits the work and leaves a clean tree without plans/" {
  full
  assert_equal "$(git -C "$H" log -1 --format=%s)" "WIP: stopped at usage limit — y"
  assert_equal "$(git -C "$H" status --porcelain)" ""
  has "$(git -C "$H" log -1 --format=%b)" "^Co-Authored-By: Claude <noreply@anthropic.com>\$"
  assert_equal "$(git -C "$H" ls-files plans)" ""
}

# old: handoff: --jobs lists the relaunch
@test "the handoff relaunch is listed by --jobs" {
  full
  has "$(ra --jobs)" '^#[0-9]*  claude --agent worker "." --model haiku --name "worker: handoff (haiku)"  at .* ET live (after window, in 2m)  \[sleeping (pid [0-9]*)\]$'
}

# old: handoff: outside tmux -> exit 0, note + commit, not-scheduled Relaunch
@test "handoff outside tmux still writes note and commit and says nothing was scheduled" {
  unset TMUX TMUX_PANE
  handoff 'Done: x\nIn progress:\n- half of b\nNext: z\n' worker
  assert_success
  assert_equal "$(line 3 "$output")" "$NOT_IN_TMUX"
  assert_equal "$(git -C "$H" log -1 --format=%s)" "WIP: stopped at usage limit — half of b"
  assert_equal "$(tail -n 1 "$H/plans/WORKER_NOTES.md")" "$NOT_IN_TMUX"
  # old: handoff: not-in-tmux fallback scheduled nothing
  assert_equal "$(ra --jobs)" "no scheduled runs"
}

# old: handoff: API without a reset -> scheduled at now + 5 h, note + commit
@test "handoff with no reset from the API still schedules, notes and commits" {
  echo '{}' > "$T/empty.json"
  RUN_AGENT_USAGE_FILE="$T/empty.json" handoff 'In progress: c\n' worker
  assert_success
  has "$(line 3 "$output")" "^Relaunch: .* ET (job #[0-9]*)\$"
  assert_equal "$(git -C "$H" log -1 --format=%s)" "WIP: stopped at usage limit — c"
}

# old: handoff: empty stdin -> heading + Uncommitted + Relaunch only
@test "handoff with no text on a clean tree writes only heading, dirty line and relaunch" {
  git -C "$H" add -A
  git -C "$H" commit -q -m clean
  handoff '' worker
  assert_success
  assert_equal "$(line 2 "$output")" "Commit: nothing to commit"
  local n; n="$(tail -n 3 "$H/plans/WORKER_NOTES.md")"
  has "$(line 1 "$n")" "^## Stopped at usage limit — .* ET\$"
  assert_equal "$(line 2 "$n")" "Uncommitted/dirty: none"
  has "$(line 3 "$n")" "^Relaunch: .* ET (job #[0-9]*)\$"
}

# old: handoff: non-git dir -> Commit: no git
@test "handoff outside a git repository writes the note and says there is no git" {
  H="$T/nogit"; mkdir -p "$H"
  handoff 'Next: z\n' worker
  assert_success
  assert_equal "$(line 2 "$output")" "Commit: no git"
  fhas "$H/plans/WORKER_NOTES.md" "^Next: z\$"
}

# old: handoff: 3 at once: the three writers were not held together | handoff: 3 at once in one frozen instant -> 3 distinct job ids, each job its own lane's folder
# bats test_tags=escape:4
@test "three handoffs at the same instant get three job ids, each for its own folder" {
  usage_at $(( $(date +%s) + 600 ))
  local frozen i id ids="" own=0
  frozen=$(date +%s)
  mkdir -p "$T/sync/seen"
  mkfifo "$T/sync/go"
  for i in 1 2 3; do
    mkdir -p "$T/lane$i"; git -C "$T/lane$i" init -q; git -C "$T/lane$i" commit -q --allow-empty -m init
  done
  for i in 1 2 3; do
    ( cd "$T/lane$i" && printf 'Next: lane %s\n' "$i" | PYTHONPATH="$RA_FIX/sync" RA_SYNC_DIR="$T/sync/seen" RA_SYNC_GO="$T/sync/go" RUN_AGENT_NOW="$frozen" ra --handoff worker "lane $i" > "$T/lane$i.out" 2>&1 ) 3>&- &
  done
  wait
  assert_equal "$(ls "$T/sync/seen" | wc -l)" 3
  for i in 1 2 3; do
    id="$(sed -n 's/^Relaunch: .* ET (job #\([0-9]*\))$/\1/p' "$T/lane$i.out")"
    [ -n "$id" ] || { cat "$T/lane$i.out"; return 1; }
    assert_equal "$(jget "$id" cwd)" "$T/lane$i"
    ids="$ids$id
"
  done
  assert_equal "$(printf '%s' "$ids" | sort -u | wc -l)" 3
  assert_equal "$(ra --jobs | grep -c '^#')" 3
}

@test "a handoff keeps plans/ out of the commit even when git does not ignore it" {
  rm "$H/.gitignore"
  full
  assert_success
  assert_equal "$(git -C "$H" ls-files a.txt)" "a.txt"
  assert_equal "$(git -C "$H" ls-files plans)" ""
  assert_file_exist "$H/plans/WORKER_NOTES.md"
}
