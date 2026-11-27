# run_legacy <script> [args...]: `run` an old test script that is not yet split into @test cases. On macOS it
# goes through test/stock-mac.sh (/bin/bash 3.2, empty environment, stock PATH), as the old CI job ran it.
# Each use is a debt: the script's checks move into @test cases and the script is deleted (TESTING.md).
# Its output goes to a file, not a pipe, and fd 3 is closed: these scripts leave background processes (a
# fake claude's sleep) that would keep a pipe open and hold bats for minutes after the script has ended.
run_legacy() {
  local log="$BATS_TEST_TMPDIR/legacy.out"
  status=0
  if [ "$(uname -s)" = Darwin ]; then /bin/bash "$REPO/test/stock-mac.sh" "$@" >"$log" 2>&1 3>&- </dev/null || status=$?
  else bash "$@" >"$log" 2>&1 3>&- </dev/null || status=$?; fi
  output="$(cat "$log")"
}
on_windows() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac; return 1; }
