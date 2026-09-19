#!/usr/bin/env bash
# Detect the test runner and report everything a speedup pass needs.
# Bundled because every run of this skill otherwise re-derives the same
# jq/awk incantations per stack — and because `baseline` collapses what
# used to be three separate full-suite runs into one.
#
#   measure.sh detect             -> runner name, or "unknown"
#   measure.sh baseline [N] [-- args]
#        -> ONE full run emitting WALL_SECONDS, EXIT, COUNT and the N
#           slowest tests. Use this instead of run+count+profile.
#   measure.sh run [-- args]      -> runs the suite, prints WALL_SECONDS/EXIT
#   measure.sh time -- <cmd...>   -> times ANY command under the same lock.
#        Use it on the fast-tier and changed-files commands: they are the ones
#        the agent actually runs all day, and an unmeasured claim about them
#        is the usual way a "3x faster" report turns out to be worthless.
#   measure.sh count              -> integer test count, no execution
#   measure.sh profile [N]        -> N slowest tests (default 25)
#   measure.sh unlock             -> clear a stale run lock
#
# Every runner invocation takes an exclusive lock. A timed run shares the
# machine with nothing: a second test process would contend for CPU and the
# wall-clock number becomes fiction. Launch ONE run in the background, do the
# edits that don't touch the runner's files while it goes, then join.
#
# Set RESULT_FILE to have the parsed result block written there as well as to
# stdout, so a backgrounded run's numbers survive without scrollback. It is
# appended, so give each run its own file — or read the last block, the one
# terminated by DONE. A file with no DONE line is a run still in flight.
#
# Exit 3 = no supported runner found. Exit 4 = another run is already in
# flight. Anything else is the runner's own status.
set -uo pipefail

CAP_SECONDS="${CAP_SECONDS:-900}"
OUT="${TMPDIR:-/tmp}/measure-$$"
RESULT_FILE="${RESULT_FILE:-}"
# Lock lives in TMPDIR, never the worktree: this skill requires a clean
# `git status` and commits per step, so run state must not dirty the repo.
LOCKDIR="${TMPDIR:-/tmp}/test-speedup.lock"

cleanup() { rm -f "$OUT" "$OUT.json"; [ "${HELD_LOCK:-0}" = 1 ] && rm -rf "$LOCKDIR"; return 0; }
trap cleanup EXIT

# mkdir is atomic, so this is a real mutex rather than a check-then-write race.
acquire_lock() {
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo $$ >"$LOCKDIR/pid"; HELD_LOCK=1; return 0
  fi
  local other; other=$(cat "$LOCKDIR/pid" 2>/dev/null)
  if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
    echo "measure.sh: run already in flight (pid $other). Two test processes contend" >&2
    echo "  for CPU and ruin the timing. Join that run first, or 'measure.sh unlock'." >&2
    return 4
  fi
  # Stale lock from a killed run — take it over.
  echo "measure.sh: clearing stale lock from pid ${other:-?}" >&2
  rm -rf "$LOCKDIR"; mkdir "$LOCKDIR" 2>/dev/null || return 4
  echo $$ >"$LOCKDIR/pid"; HELD_LOCK=1; return 0
}

emit() { if [ -n "$RESULT_FILE" ]; then tee -a "$RESULT_FILE"; else cat; fi; }

# macOS ships neither timeout nor gtimeout; degrade to uncapped rather than
# failing the whole step on a missing binary.
cap() {
  if command -v timeout >/dev/null 2>&1; then timeout "$CAP_SECONDS" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$CAP_SECONDS" "$@"
  else echo "measure.sh: no timeout binary, running uncapped" >&2; "$@"
  fi
}

need_jq() { command -v jq >/dev/null 2>&1 || { echo "measure.sh: jq not installed; falling back" >&2; return 1; }; }
has_dep() { grep -qE "$1" package.json 2>/dev/null; }

detect() {
  if [ -f go.mod ]; then echo go
  elif [ -f Cargo.toml ]; then echo rust
  elif has_dep '"vitest"'; then echo vitest
  elif has_dep '"jest"'; then echo jest
  elif [ -f Gemfile ] && grep -qi rspec Gemfile 2>/dev/null; then echo rspec
  elif ls build.gradle build.gradle.kts >/dev/null 2>&1; then echo gradle
  elif [ -f pom.xml ]; then echo maven
  elif command -v pytest >/dev/null 2>&1 && ls pyproject.toml pytest.ini setup.cfg tox.ini >/dev/null 2>&1; then echo pytest
  else echo unknown
  fi
}

RUNNER="$(detect)"
CMD="${1:-detect}"; shift 2>/dev/null || true

# ---------------------------------------------------------------- baseline --
# One execution, three numbers. Every runner here can emit per-test timing as
# a side effect of the run it was going to do anyway, so profiling is free.
baseline() {
  # N is optional and must be numeric; everything after `--` goes to the runner.
  local n=25
  case "${1:-}" in ''|*[!0-9]*) : ;; *) n="$1"; shift ;; esac
  [ "${1:-}" = "--" ] && shift
  local start status count
  start=$(date +%s)

  case "$RUNNER" in
    pytest)
      cap pytest -q -p no:randomly --durations="$n" "$@" >"$OUT" 2>&1; status=$?
      count=$(grep -oE '[0-9]+ (passed|failed|skipped|xfailed|xpassed|error)' "$OUT" \
              | awk '{s+=$1} END{print s+0}')
      ;;
    jest)
      cap npx jest --silent --json --outputFile="$OUT.json" >"$OUT" 2>&1; status=$?
      if need_jq; then count=$(jq -r '.numTotalTests // 0' "$OUT.json" 2>/dev/null); fi
      ;;
    vitest)
      cap npx vitest run --reporter=json --outputFile="$OUT.json" >"$OUT" 2>&1; status=$?
      if need_jq; then count=$(jq -r '.numTotalTests // 0' "$OUT.json" 2>/dev/null); fi
      ;;
    go)
      cap go test -count=1 -json ./... "$@" >"$OUT.json" 2>/dev/null; status=$?
      if need_jq; then
        count=$(jq -rs '[.[] | select(.Test!=null and (.Action=="pass" or .Action=="fail" or .Action=="skip")) | .Package+"."+.Test] | unique | length' "$OUT.json" 2>/dev/null)
      fi
      ;;
    rust)
      cap cargo nextest run "$@" >"$OUT" 2>&1; status=$?
      count=$(grep -oE 'Summary \[[^]]*\] +[0-9]+ tests? run' "$OUT" | grep -oE '[0-9]+ tests? run' | grep -oE '^[0-9]+')
      ;;
    rspec)
      cap bundle exec rspec --profile "$n" "$@" >"$OUT" 2>&1; status=$?
      count=$(grep -oE '^[0-9]+ examples?' "$OUT" | grep -oE '[0-9]+' | tail -1)
      ;;
    gradle)  cap ./gradlew test "$@" >"$OUT" 2>&1; status=$? ;;
    maven)   cap mvn test "$@" >"$OUT" 2>&1; status=$? ;;
    *) echo "baseline unsupported for $RUNNER" >&2; return 3 ;;
  esac

  {
    echo "RUNNER=$RUNNER"
    echo "WALL_SECONDS=$(( $(date +%s) - start ))"
    echo "EXIT=$status"
    case "$RUNNER" in
      gradle|maven) echo "COUNT=$(xml_count)" ;;
      *) echo "COUNT=${count:-unknown}" ;;
    esac
    echo "SLOWEST"
    slowest_from_run "$n"
    # Failures matter more than timing; surface them without dumping the run.
    if [ "$status" != 0 ]; then
      echo "FAILURES"
      grep -iE '^(FAIL|not ok|--- FAIL|\s*[0-9]+\) )|^E  ' "$OUT" 2>/dev/null | head -40
    fi
    echo "DONE"
  } | emit
  return "$status"
}

xml_count() {
  find . \( -path '*test-results*' -o -path '*surefire-reports*' \) -name '*.xml' 2>/dev/null \
    | xargs grep -ho '<testcase ' 2>/dev/null | wc -l | tr -d ' '
}

# Pull per-test timings out of the artifacts the baseline run just produced.
slowest_from_run() {
  local n="$1"
  case "$RUNNER" in
    pytest) grep -E '^[0-9.]+s' "$OUT" | head -"$n" ;;
    jest)   need_jq && jq -r '.testResults[].assertionResults[] | [(.duration//0)/1000, .fullName] | @tsv' "$OUT.json" 2>/dev/null | sort -rn | head -"$n" ;;
    vitest) need_jq && jq -r '.testResults[].assertionResults[] | [(.duration//0)/1000, .fullName] | @tsv' "$OUT.json" 2>/dev/null | sort -rn | head -"$n" ;;
    go)     need_jq && jq -rs '.[] | select(.Test!=null and (.Action=="pass" or .Action=="fail")) | [.Elapsed, (.Package+"."+.Test)] | @tsv' "$OUT.json" 2>/dev/null | sort -rn | head -"$n" ;;
    rust)   grep -oE '(PASS|FAIL) \[ *[0-9.]+s\] +\S+ +\S+' "$OUT" | sed -E 's/^[A-Z]+ \[ *([0-9.]+)s\] +(.*)$/\1\t\2/' | sort -rn | head -"$n" ;;
    rspec)  sed -n '/Top .* slowest/,/^$/p' "$OUT" ;;
    gradle|maven)
            find . \( -path '*test-results*' -o -path '*surefire-reports*' \) -name '*.xml' 2>/dev/null \
              | xargs grep -ho 'testcase name="[^"]*"[^>]*time="[^"]*"' 2>/dev/null \
              | sed 's/.*name="\([^"]*\)".*time="\([^"]*\)"/\2\t\1/' | sort -rn | head -"$n" ;;
    *) echo "(no per-test timing for $RUNNER)" ;;
  esac
}

case "$CMD" in
  detect) echo "$RUNNER"; [ "$RUNNER" = unknown ] && exit 3; exit 0 ;;

  baseline) acquire_lock || exit 4; baseline "$@"; exit $? ;;

  unlock) rm -rf "$LOCKDIR"; echo "lock cleared"; exit 0 ;;

  count)
    acquire_lock || exit 4
    case "$RUNNER" in
      pytest) pytest --collect-only -q 2>/dev/null | grep -cE '::' ;;
      jest)   npx jest --listTests 2>/dev/null | wc -l | tr -d ' '; echo "(files, not tests — prefer 'baseline')" >&2 ;;
      vitest) npx vitest list 2>/dev/null | grep -c '>' ;;
      go)     go test -list '.*' ./... 2>/dev/null | grep -c '^Test' ;;
      rust)   cargo nextest list 2>/dev/null | grep -cE '^\s+\w' ;;
      rspec)  bundle exec rspec --dry-run -f progress 2>/dev/null | grep -oE '[0-9]+ examples?' | head -1 | grep -oE '[0-9]+' ;;
      *) echo "count unsupported for $RUNNER" >&2; exit 3 ;;
    esac ;;

  run)
    acquire_lock || exit 4
    [ "${1:-}" = "--" ] && shift
    start=$(date +%s)
    case "$RUNNER" in
      pytest) cap pytest -q -p no:randomly "$@" ;;
      jest)   cap npx jest --silent "$@" ;;
      vitest) cap npx vitest run "$@" ;;
      go)     cap go test -count=1 ./... "$@" ;;
      rust)   cap cargo nextest run "$@" ;;
      rspec)  cap bundle exec rspec "$@" ;;
      gradle) cap ./gradlew test "$@" ;;
      maven)  cap mvn test "$@" ;;
      *) echo "run unsupported for $RUNNER" >&2; exit 3 ;;
    esac
    status=$?
    { echo "WALL_SECONDS=$(( $(date +%s) - start ))"; echo "EXIT=$status"; echo "DONE"; } | emit
    exit $status ;;

  # Timing an arbitrary command — the fast tier, the slow tier, one file. Takes
  # the lock like everything else so it can't land on top of a full run.
  time)
    acquire_lock || exit 4
    [ "${1:-}" = "--" ] && shift
    [ $# -gt 0 ] || { echo "usage: measure.sh time -- <command...>" >&2; exit 2; }
    start=$(date +%s)
    cap "$@"
    status=$?
    { echo "CMD=$*"; echo "WALL_SECONDS=$(( $(date +%s) - start ))"; echo "EXIT=$status"; echo "DONE"; } | emit
    exit $status ;;

  # profile is a full run either way, so it is just baseline under another
  # name — it returns timing and count too. Kept for backward compatibility.
  profile) acquire_lock || exit 4; baseline "$@"; exit $? ;;

  *) echo "usage: measure.sh {detect|baseline [N]|run|time -- <cmd>|count|profile|unlock}" >&2; exit 2 ;;
esac
