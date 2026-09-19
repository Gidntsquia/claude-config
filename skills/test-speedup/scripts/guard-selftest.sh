#!/usr/bin/env bash
# Verify an installed full-suite guard actually blocks and actually allows.
# Run from the target repo root AFTER writing .claude/test-commands.sh:
#   bash <skill>/scripts/guard-selftest.sh .claude/hooks/full-suite-guard.sh
# A guard that blocks everything is worse than none — it makes the agent stop
# running tests at all — so the allow cases matter as much as the block cases.
set -uo pipefail
G="${1:-}"
if [ -z "$G" ]; then
  for c in .claude/hooks/full-suite-guard.sh "$HOME/.claude/hooks/full-suite-guard.sh"; do
    [ -f "$c" ] && { G="$c"; break; }
  done
fi
[ -n "$G" ] && [ -f "$G" ] || { echo "no guard found (repo or ~/.claude/hooks)" >&2; exit 1; }
# The commands file is the guard's on switch, so without it every case returns
# 0 and the block half of this test silently "passes".
[ -f .claude/test-commands.sh ] || {
  echo "no .claude/test-commands.sh in $PWD — write it first, or the guard is inert" >&2; exit 1; }
echo "guard: $G"
FULL_CMD=""
# shellcheck disable=SC1091
[ -f .claude/test-commands.sh ] && . .claude/test-commands.sh
RUNNER="${2:-$(bash "$(dirname "$0")/measure.sh" detect 2>/dev/null)}"

fail=0
check() { # $1 expected rc, $2 command
  local out rc
  out=$(printf '{"session_id":"selftest","tool_input":{"command":%s}}' \
        "$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" | bash "$G" 2>&1)
  rc=$?
  if [ "$rc" != "$1" ]; then
    printf 'FAIL want=%s got=%s  %s\n' "$1" "$rc" "$2"; fail=1
  else
    printf 'ok   rc=%s  %s\n' "$rc" "$2"
  fi
}

# Universal: never touch non-test commands, always honour the override.
check 0 "git status"
check 0 "grep -rn pytest ."
check 0 "TS_FULL=1 ${FULL_CMD:-pytest}"
check 0 "scripts/measure.sh baseline 25"

case "$RUNNER" in
  pytest) check 2 "pytest"; check 2 "pytest -q"; check 2 "python -m pytest"
          check 0 "pytest tests/test_x.py"; check 0 "pytest -k auth"; check 0 "pytest -m slow" ;;
  jest)   check 2 "npx jest"; check 2 "npm test"
          check 0 "npx jest src/x.test.ts"; check 0 "npx jest --onlyChanged"; check 0 "npm run test:fast" ;;
  vitest) check 2 "npx vitest run"; check 2 "npm test"
          check 0 "npx vitest run src/x.test.ts"; check 0 "npx vitest run --changed origin/main" ;;
  go)     check 2 "go test ./..."; check 0 "go test ./pkg/auth"; check 0 "go test -run TestX ./..." ;;
  rust)   check 2 "cargo nextest run"; check 2 "cargo test"; check 0 "cargo nextest run -E 'test(x)'" ;;
  rspec)  check 2 "bundle exec rspec"; check 0 "bundle exec rspec spec/x_spec.rb"; check 0 "bundle exec rspec -t slow" ;;
  gradle) check 2 "./gradlew test"; check 0 "./gradlew test --tests '*XTest'" ;;
  maven)  check 2 "mvn test"; check 0 "mvn test -Dtest=XTest" ;;
  *) echo "(runner '$RUNNER' unknown — universal checks only)" ;;
esac

[ "$fail" = 0 ] && echo "guard selftest: PASS" || echo "guard selftest: FAIL"
exit "$fail"
