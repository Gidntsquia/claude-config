# For test/quick/install-*.bats. Each file runs one scenario once, in setup_file; each @test then reads the
# result of the checks it names, so any one test can run alone (bats --filter) and in any order.
install_setup_file() {  # <scenario>
  local cmd rc=0
  export SCN_OUT="$BATS_FILE_TMPDIR/scn"
  mkdir -p "$SCN_OUT" && : > "$SCN_OUT/checks"
  BATS_TEST_TMPDIR="$BATS_FILE_TMPDIR" temp_home   # the driver's own HOME; it makes a further home per scenario
  export SCN_REAL_HOME="$REAL_HOME"                # where the Claude Code install is; read, never written
  if [ -n "${CI:-}" ]; then export SCN_NEED_OLDTAG=1; fi
  # On macOS: /bin/bash 3.2, empty environment, stock PATH.
  cmd=(bash)
  [ "$(uname -s)" != Darwin ] || cmd=(/bin/bash "$REPO/test/helpers/stock-mac.sh")
  without_bats_fds "${cmd[@]}" "$REPO/test/helpers/install-run.bash" "$1" > "$SCN_OUT/log" 2>&1 < /dev/null || rc=$?
  echo "$rc" > "$SCN_OUT/rc"
}
# The driver removes each home itself; this covers a run that was cut short.
install_teardown_file() {
  local h
  [ -f "${SCN_OUT:-}/homes" ] || return 0
  while IFS= read -r h; do
    case "$h" in */cc-install-*) rm -rf "$h" ;; esac
  done < "$SCN_OUT/homes"
}
skip_if_not_run() { if [ -f "$SCN_OUT/skip" ]; then skip "$(cat "$SCN_OUT/skip")"; fi; }
show_run() {
  echo "-- failed checks:"; grep '^FAIL' "$SCN_OUT/checks" || echo "(none)"
  echo "-- last lines of the run (exit $(cat "$SCN_OUT/rc" 2>/dev/null)):"; tail -n 60 "$SCN_OUT/log"
}
# passed [-n <count>] <start of a check's label>: exactly <count> checks (default 1) start with that text and every
# one of them passed. A check that never ran is a failure.
passed() {
  local want=1 got failed
  if [ "$1" = -n ]; then want="$2"; shift 2; fi
  skip_if_not_run
  got="$(P="$1" awk -F'\t' 'index($2, ENVIRON["P"]) == 1 { n++ } END { print n+0 }' "$SCN_OUT/checks")"
  failed="$(P="$1" awk -F'\t' '$1 != "ok" && index($2, ENVIRON["P"]) == 1 { print $2 }' "$SCN_OUT/checks")"
  if [ "$got" = "$want" ] && [ -z "$failed" ]; then return 0; fi
  if [ -n "$failed" ]; then printf 'failed: %s\n' "$failed"
  else echo "expected $want check(s) starting '$1', the run made $got"; fi
  show_run
  return 1
}
# The run as a whole: it reached its end, exit 0, no failed check, and on macOS it compared the real keychains.
ran_clean() {
  skip_if_not_run
  if [ ! -f "$SCN_OUT/done" ] || [ "$(cat "$SCN_OUT/rc")" != 0 ] || grep -q '^FAIL' "$SCN_OUT/checks"; then show_run; return 1; fi
  if [ "$(uname -s)" = Darwin ]; then passed "the real keychain search list and default keychain are as they were at the start"; fi
}
on_win_run() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac; return 1; }
# Whether the scenario installed with --terminal (the same default as install-lib.bash).
terminal_run() {
  case "${SCN_TERMFLAG:-}" in
    --terminal) return 0 ;;
    --no-terminal) return 1 ;;
  esac
  ! on_win_run && [ -z "${WSL_DISTRO_NAME:-}" ]
}
