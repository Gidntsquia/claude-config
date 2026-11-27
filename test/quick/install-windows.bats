#!/usr/bin/env bats
# Scenario windows: CLAUDE_CONFIG_INSTALL_OS=windows with symlinks refused. It is what install.sh does when told it
# is on Windows without WSL; the real Git Bash run of the install tests is on the Windows CI runner.

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file windows; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:windows-install
@test "windows: install.sh succeeds and copies what it cannot link" {
  passed "windows: install.sh exits 0"
  passed "windows: it says it copied"
  passed "windows: the planner agent is a real file"
  passed "windows: every installed agent and skill"
}

# bats test_tags=feature:windows-install
@test "windows: status line, tmux setup and run-agent are skipped and named" {
  passed "windows: it names what is skipped"
  passed "windows: no status line"
  passed "windows: no tmux setup"
}

# bats test_tags=feature:windows-install,feature:install-check
@test "windows: --check accepts the copies" {
  passed "windows: --check exits 0"
  passed "windows: --check passes every agent and skill"
}

# bats test_tags=feature:windows-install
@test "windows: a rerun succeeds and the clone is unchanged" {
  passed "windows: a rerun replaces"
  passed "windows: the rerun keeps none"
  passed "windows: the clone is unchanged"
}

# bats test_tags=feature:windows-install,escape:windows-stale-copy
@test "windows: a rerun after an update refreshes unedited copies and keeps edited ones" {
  passed -n 2 "windows: a rerun after an update refreshes"
  passed "windows: a copy you edited is kept"
}

# bats test_tags=feature:windows-install
@test "windows: the whole scenario ran to its end with no failed check" {
  ran_clean
}

# bats test_tags=feature:windows-install,escape:6
@test "windows: the test workflow runs the quick tier on Windows for every push to main and pull request" {
  run python3 -I -c '
import re, sys
y = open(sys.argv[1]).read()
on = y[y.index("\non:"):y.index("\njobs:")]
job = re.search(r"\n  test:\n(.*?)(?=\n  [a-z-]+:\n|\Z)", y, re.S).group(1)
assert re.search(r"\n  push:\n    branches: \[main\]", on), "not on push to main"
assert re.search(r"\n  pull_request:", on), "not on pull requests"
assert re.search(r"os: \[[^]]*windows-latest", job), "no Windows runner in the test job"
assert re.search(r"run: test/run quick\n", job), "the test job does not run the quick tier"
print("ok")' "$REPO/.github/workflows/install.yml"
  assert_output "ok"
}
