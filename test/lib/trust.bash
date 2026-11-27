# The trust modes of test/run (sourced by it): one feature's tests, planted faults, repeated runs, the report.
#   test/run --only <feature>            the quick and machine tests tagged feature:<id>
#   test/run --faults [<feature>...]     apply each test/faults/<feature>/*.patch in a scratch clone, expect FAIL
#   test/run quick --repeat <n> [--seed <s>]   the tier <n> times, file order shuffled by the seed
#   test/run --agree <file>...           add up the `run ...` lines of several repeat results (CI shards)
#   test/run --report                    rewrite the trust report block in TESTING.md
# A full run of --faults or --repeat records its result in test/results/, which --report reads.
# Scratch folders live under one mktemp folder, which test/run removes when it exits.

RESULTS="$HERE/results"

scratch() { # sets WORK_EXTRA to a new scratch folder
  WORK_EXTRA="$(mktemp -d "${TMPDIR:-/tmp}/test-trust.XXXXXX")" || { echo "test/run: no scratch folder" >&2; exit 2; }
  # the real path: on macOS TMPDIR is behind a symlink, and a clone must see one spelling of its own folder
  WORK_EXTRA="$(cd "$WORK_EXTRA" && pwd -P)"
}

stamp() { # <now in ET> on <os>, commit <c>
  local c
  c="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  [ -z "$(git -C "$REPO" status --porcelain 2>/dev/null | grep -v ' test/results/\| TESTING.md')" ] || c="$c with uncommitted changes"
  echo "$(TZ=America/New_York date '+%Y-%m-%d %I:%M %p ET') on $(uname -s), commit $c"
}

# ---- one feature --------------------------------------------------------------------------------------------
# has_tag <file> <tag>: the file carries the tag (a bats tag line, or `# <tag>` in a pytest file)
has_tag() { grep -qE "^[[:space:]]*#[[:space:]]*(bats[[:space:]]+(file|test)_tags=(.*,)?[[:space:]]*)?$2([[:space:],]|\$)" "$1"; }

run_only() {
  local t
  find_bats
  ONLY_TAG="feature:$1"
  for t in quick machine; do
    tier_now="$t"
    run_bats "$t"
  done
  run_pytest
  [ "$total" -gt 0 ] || { echo "test/run: no test is tagged $ONLY_TAG" >&2; exit 2; }
}

# ---- planted faults -----------------------------------------------------------------------------------------
feature_ids() { sed -n 's/^[[:space:]]*\([a-z0-9-][a-z0-9-]*\)[[:space:]]*|.*/\1/p' "$HERE/features.txt"; }

scratch_git() { git -c user.name=faults -c user.email=faults@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

# make_base <dir> <index file>: a clone of this repo holding the working tree as it is now, as a commit (tests
# clone it again). The commit is built through a throwaway index, so the repo's own index and files are untouched.
make_base() {
  local base="$1" index="$2" tree commit
  cp "$(cd "$REPO" && git rev-parse --git-path index | sed "s|^[^/]|$REPO/&|")" "$index" || return 1
  GIT_INDEX_FILE="$index" git -C "$REPO" add -A || return 1
  tree="$(GIT_INDEX_FILE="$index" git -C "$REPO" write-tree)" || return 1
  commit="$(scratch_git -C "$REPO" commit-tree "$tree" -p HEAD -m 'the working tree')" || return 1
  git clone -q --no-checkout "$REPO" "$base" || return 1
  git -C "$base" fetch -q "$REPO" "$commit" && git -C "$base" checkout -q -B faults-base "$commit"
}

# fault_run <id> <work dir> <clone>: the clone's tests of <id>. A runner with a planted fault must not be the one
# that judges itself, so for test-runner the unfaulted runner runs the tests and they exercise the clone's.
fault_run() {
  if [ "$1" = test-runner ]; then TEST_RUNNER_UNDER_TEST="$3/test" "$2/base/test/run" --only "$1"
  else "$3/test/run" --only "$1"; fi
}

# fault_feature <id> <work dir>: the baseline, then each patch. One line per patch in <work>/<id>.result.
fault_feature() {
  local id="$1" w="$2" p name short c rc base_rc out="$2/$1.result" patches=()
  : > "$out"
  for p in "$HERE/faults/$id"/*.patch; do [ -f "$p" ] && patches[${#patches[@]}]="$p"; done
  [ "${#patches[@]}" -gt 0 ] || return 0
  # a feature that only a person tests: its faults are planted faults nothing catches
  if grep -qE "^[[:space:]]*$id[[:space:]]*\|[^|]*\|[[:space:]]*(manual|untested):" "$HERE/features.txt"; then
    for p in "${patches[@]}"; do echo "missed $id/$(basename "$p" .patch): the feature has no automated test" >> "$out"; done
    return 0
  fi
  c="$w/$id.base"
  git clone -q "$w/base" "$c" && fault_run "$id" "$w" "$c" > "$w/$id.base.log" 2>&1; base_rc=$?
  for p in "${patches[@]}"; do
    short="$(basename "$p" .patch)"; name="$id/$short"
    if [ "$base_rc" != 0 ]; then echo "error $name: the tests of $id do not pass without the fault (exit $base_rc)" >> "$out"; continue; fi
    c="$w/$id.$short"
    git clone -q "$w/base" "$c"
    if grep -E '^(\+\+\+|---) [ab]/test/' "$p" | grep -qvE "$([ "$id" = test-runner ] && echo ' [ab]/test/(run([[:space:]]|$)|lib/)' || echo '^$')"; then echo "error $name: a fault may not edit test/" >> "$out"
    elif ! git -C "$c" apply --whitespace=nowarn "$p" 2>"$w/apply.$id"; then echo "error $name: the patch does not apply: $(head -1 "$w/apply.$id")" >> "$out"
    else
      git -C "$c" add -A && scratch_git -C "$c" commit -q -m "fault $name"
      fault_run "$id" "$w" "$c" > "$w/$id.$short.log" 2>&1; rc=$?
      case "$rc" in
        1) echo "caught $name" >> "$out" ;;
        0) echo "missed $name" >> "$out" ;;
        *) echo "error $name: test/run exited $rc" >> "$out" ;;
      esac
    fi
  done
}

run_faults() {
  local w ids="$*" id full=0 jobs="${FAULT_JOBS:-3}" n m count short=0
  [ -n "$ids" ] || { full=1; ids="$(feature_ids)"; }
  for id in $ids; do
    feature_ids | grep -qx -- "$id" || { echo "test/run: no feature $id in test/features.txt" >&2; exit 2; }
  done
  scratch; w="$WORK_EXTRA"
  make_base "$w/base" "$w/index" || { echo "test/run: could not make the scratch clone" >&2; exit 2; }
  for id in $ids; do
    while [ "$(jobs -rp | wc -l)" -ge "$jobs" ]; do sleep 0.5; done
    ( trap - EXIT; export TEST_JOBS="${TEST_JOBS:-2}"; fault_feature "$id" "$w"; cat "$w/$id.result" ) &
  done
  wait
  : > "$w/all"
  for id in $ids; do
    cat "$w/$id.result" >> "$w/all"
    count="$(grep -c . "$w/$id.result")"
    [ "$count" -ge 3 ] || { echo "short $id: $count of 3 faults planted" >> "$w/all"; short=1; }
  done
  n="$(grep -c '^caught ' "$w/all")"
  m="$(grep -cE '^(caught|missed|error) ' "$w/all")"
  echo "== faults"
  sort "$w/all"
  if [ "$full" = 1 ]; then
    mkdir -p "$RESULTS"
    { echo "# test/run --faults, $(stamp)"; sort "$w/all"; echo "caught $n of $m"; } > "$RESULTS/faults.txt"
  fi
  if [ -n "${FAULT_LOGS:-}" ]; then mkdir -p "$FAULT_LOGS" && cp "$w"/*.log "$FAULT_LOGS"/; fi
  echo "caught $n of $m"
  [ "$n" = "$m" ] && [ "$short" = 0 ]
}

# ---- repeated runs ------------------------------------------------------------------------------------------
# shuffle <seed>: stdin lines in an order that depends only on the seed and the lines
shuffle() { awk -v s="$1" 'BEGIN { srand(s) } { printf "%.12f\t%s\n", rand(), $0 }' | sort | cut -f2-; }

# agree <file of `run <i> seed <s>: <result>` lines> [<planned>]: prints `agreed <n> of <m>`, n being the runs with
# the commonest result; status 0 only when every planned run passed with one and the same result.
agree() {
  awk -v planned="${2:-0}" '
    /^run / { r = $0; sub(/^[^:]*: /, "", r); count[r]++; m++ }
    END {
      best = 0
      for (r in count) if (count[r] > best || (count[r] == best && r ~ /^PASS /)) { best = count[r]; top = r }
      if (planned + 0 > m) m = planned + 0
      printf "agreed %d of %d\n", best, m
      exit !(m > 0 && best == m && top ~ /^PASS /)
    }' "$1"
}

run_repeat() {
  local n="$1" seed="$2" i s w result rc
  find_bats
  scratch; w="$WORK_EXTRA"
  echo "seed $seed ($n runs; run <i> shuffles by seed + <i> - 1)"
  : > "$w/runs"
  i=1
  while [ "$i" -le "$n" ]; do
    s=$((seed + i - 1))
    total=0; failed=0; skips=0
    tier_now=quick; SHUFFLE_SEED="$s"
    { run_bats quick; run_pytest; } > "$w/log" 2>&1
    if [ "$failed" -eq 0 ]; then result="PASS $total tests"
    else
      result="FAIL $failed of $total [$(grep -E '^(not ok|FAILED) ' "$w/log" | sed 's/^not ok [0-9]* //' | sort | tr '\n' ';')]"
      cat "$w/log"
    fi
    echo "run $i seed $s: $result" | tee -a "$w/runs"
    i=$((i + 1))
  done
  result="$(agree "$w/runs" "$n")"; rc=$?
  mkdir -p "$RESULTS"
  { echo "# test/run quick --repeat $n --seed $seed, $(stamp)"; cat "$w/runs"; echo "$result"; } > "$RESULTS/repeat.txt"
  echo "$result"
  return "$rc"
}

# ---- the report ---------------------------------------------------------------------------------------------
# ids of a `<id> | ...` list
list_ids() { sed -n 's/^[[:space:]]*\([A-Za-z0-9_-][A-Za-z0-9_-]*\)[[:space:]]*|.*/\1/p' "$1" 2>/dev/null; }
tagged_in() { # <tag> <dirs...>
  local t="$1" d f; shift
  for d in "$@"; do for f in "$d"/*.bats; do [ -f "$f" ] && has_tag "$f" "$t" && return 0; done; done
  return 1
}
result_head() { sed -n '1s/^# [^,]*, //p' "$1"; }
result_count() { sed -n "s/^$2 \([0-9]* of [0-9]*\)\$/\1/p" "$1"; }

report_block() {
  local list="$HERE/features.txt" all untested n id have=0 m=0 missing="" sh=0 sm=0 smissing="" f
  all="$(feature_ids | grep -c .)"
  untested="$(awk -F'|' '!/^[ \t]*(#|$)/ { c = $3; gsub(/^[ \t]+|[ \t\r]+$/, "", c); id = $1; gsub(/[ \t]/, "", id); if (c ~ /^(manual|untested):/) printf "- `%s`: %s\n", id, c }' "$list")"
  n=$((all - $(printf '%s' "$untested" | grep -c '^- ')))
  for id in $(list_ids "$HERE/escapes.txt"); do
    m=$((m + 1))
    if tagged_in "escape:$id" "$HERE/quick" "$HERE/machine" "$HERE/docker"; then have=$((have + 1)); else missing="$missing $id"; fi
  done
  for id in $(list_ids "$HERE/standins.txt"); do
    sm=$((sm + 1))
    if tagged_in "standin:$id" "$HERE/machine"; then sh=$((sh + 1)); else smissing="$smissing $id"; fi
  done
  echo "| Number | Value | Answers |"
  echo "|---|---|---|"
  echo "| Features with automated tests | $n of $all | completeness |"
  f="$RESULTS/faults.txt"
  if [ -f "$f" ]; then echo "| Planted faults caught | $(result_count "$f" caught) | sensitivity |"
  else echo "| Planted faults caught | not run | sensitivity |"; fi
  echo "| Past real-machine errors with a test | $have of $m | fidelity |"
  f="$RESULTS/repeat.txt"
  if [ -f "$f" ]; then
    id="$(grep -cE '^run [0-9]+ seed [0-9]+: FAIL ' "$f")"
    [ "$id" = 0 ] && id="" || id=" ($id of the runs failed)"
    echo "| Repeated shuffled runs that agreed | $(result_count "$f" agreed)$id | consistency |"
  else echo "| Repeated shuffled runs that agreed | not run | consistency |"; fi
  echo "| Stand-ins with a test against the real tool | $sh of $sm | fidelity |"
  echo
  echo "Features with no automated test:"
  echo
  if [ -n "$untested" ]; then printf '%s\n' "$untested"; else echo "- none"; fi
  [ -z "$missing" ] || { echo; echo "Past errors with no test:$missing (test/escapes.txt)."; }
  [ -z "$smissing" ] || { echo; echo "Stand-ins never compared with the real tool:$smissing (reasons in test/standins.txt)."; }
  f="$RESULTS/faults.txt"
  if [ -f "$f" ]; then
    echo; echo "Faults measured $(result_head "$f")."
    if grep -qE '^(missed|error|short) ' "$f"; then echo; grep -E '^(missed|error|short) ' "$f" | sed 's/^/- /'; fi
  fi
  f="$RESULTS/escapes.txt"
  if [ -f "$f" ]; then echo; echo "Past errors seen red with their fix removed: $(result_count "$f" red), measured $(result_head "$f")."; fi
  f="$RESULTS/repeat.txt"
  if [ -f "$f" ]; then echo; echo "Repeat measured $(result_head "$f")."; fi
}

run_report() {
  local doc="$REPO/TESTING.md"
  grep -qx '<!-- trust-report:start -->' "$doc" 2>/dev/null && grep -qx '<!-- trust-report:end -->' "$doc" ||
    { echo "test/run: TESTING.md lacks the trust-report:start and trust-report:end marks" >&2; return 2; }
  scratch
  report_block > "$WORK_EXTRA/block"
  awk -v block="$WORK_EXTRA/block" '
    $0 == "<!-- trust-report:start -->" { print; while ((getline l < block) > 0) print l; skip = 1; next }
    $0 == "<!-- trust-report:end -->" { skip = 0 }
    !skip' "$doc" > "$WORK_EXTRA/doc" && cat "$WORK_EXTRA/doc" > "$doc"
  cat "$WORK_EXTRA/block"
  echo "report: TESTING.md rewritten"
}
