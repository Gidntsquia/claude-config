# The README status line (sourced by bin/release/trust-report). Needs RESULTS, REPO, WORK_EXTRA and stamp.
# record_full reads the globals failed, total and skips.
# test/results/full-<system>.txt holds the last full run on that system, one line: `<date>|<version>|<failed>|<total>|<skipped>|<stamp>`
this_system() { # prints `<system> <version>`; nothing on a system the status line does not name
  local v
  case "$(uname -s)" in
    Darwin) echo "macos $(sw_vers -productVersion 2>/dev/null)" ;;
    MINGW*|MSYS*) echo "windows" ;;
    Linux)
      v="$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${OS_RELEASE:-/etc/os-release}" 2>/dev/null)"
      grep -qx 'ID=ubuntu' "${OS_RELEASE:-/etc/os-release}" 2>/dev/null && echo "ubuntu $v" ;;
  esac
}

# status_line: `Last full run: <date>, macOS <v> / Ubuntu <v> / Windows: all <n> tests passed` when all three
# passed with the same count; otherwise each system says its own result, `not run` included.
status_line() {
  local s name f date v bad n skipped rest newest="" names="" counts="" parts="" same=1 first="" part passed=0 skips_all=0
  for s in macos ubuntu windows; do
    f="$RESULTS/full-$s.txt"
    [ -f "$f" ] || continue
    IFS='|' read -r date rest < "$f"
    [[ "$date" > "$newest" ]] && newest="$date"
  done
  for s in macos ubuntu windows; do
    case "$s" in macos) name=macOS ;; ubuntu) name=Ubuntu ;; windows) name=Windows ;; esac
    f="$RESULTS/full-$s.txt"
    if [ ! -f "$f" ]; then same=0; parts="$parts${parts:+; }$name: not run"; continue; fi
    IFS='|' read -r date v bad n skipped rest < "$f"
    name="$name${v:+ $v}"
    names="$names${names:+ / }$name"
    if [ "$bad" = 0 ]; then part="all $n tests passed"; passed=$((passed + 1))
    else part="$bad of $n tests failed"; same=0; fi
    [ "$skipped" = 0 ] || part="$part ($skipped skipped)"
    [ "$date" = "$newest" ] || { part="$part on $date"; same=0; }
    [ -n "$first" ] || first="$n"
    [ "$n" = "$first" ] || same=0
    skips_all=$((skips_all + skipped))
    parts="$parts${parts:+; }$name: $part"
  done
  if [ "$same" = 1 ] && [ "$passed" = 3 ]; then
    part="all $first tests passed"
    [ "$skips_all" = 0 ] || part="$part ($skips_all skips across the three)"
    echo "Last full run: $newest, $names: $part"
  else
    echo "Last full run: $newest, $parts"
  fi
}

record_full() {
  local sys name v readme="$REPO/README.md" line
  grep -q '^\[Last full run: ' "$readme" 2>/dev/null ||
    { echo "trust-report: README.md lacks its \`[Last full run: ...](TESTING.md)\` line" >&2; return 2; }
  sys="$(this_system)"
  if [ -z "$sys" ]; then echo "report: README.md left alone: the status line names macOS, Ubuntu and Windows"; return 0; fi
  name="${sys%% *}"; v=""
  [ "$sys" = "$name" ] || v="${sys#* }"
  mkdir -p "$RESULTS"
  echo "$(TZ=America/New_York date '+%Y-%m-%d')|$v|$failed|$total|$skips|$(stamp)" > "$RESULTS/full-$name.txt"
  line="[$(status_line)](TESTING.md)"
  awk -v line="$line" '/^\[Last full run: / { print line; next } { print }' "$readme" > "$WORK_EXTRA/readme" &&
    cat "$WORK_EXTRA/readme" > "$readme"
  echo "report: README.md says: $line"
}
