#!/usr/bin/env bats
# The real tools behind the quick tier's stand-ins, each used the way its stand-in is used (each test's `standin:<id>` tag names the stand-in).
# A difference found here means a quick test can pass while the real machine fails: fix the stand-in, then the code.

load ../helpers/common

setup() {
  temp_home
  W="$BATS_TEST_TMPDIR"
}

teardown() {
  [ -z "${TMUX_DIR:-}" ] || { env TMUX_TMPDIR="$TMUX_DIR" tmux -L standin kill-server >/dev/null 2>&1 || true; rm -rf "${TMUX_DIR:?}"; }
  [ -z "${FF_PID:-}" ] || kill -9 "$FF_PID" 2>/dev/null || true
  [ -z "${DOMAIN:-}" ] || defaults delete "$DOMAIN" >/dev/null 2>&1 || true
}

# a tmux server of this test's own, on a socket in a short folder (a socket path has a length limit)
own_tmux() {
  command -v tmux >/dev/null 2>&1 || skip "tmux missing"
  TMUX_DIR="$(mktemp -d /tmp/stin.XXXXXX)"
  unset TMUX TMUX_PANE
}
tm() { env TMUX_TMPDIR="$TMUX_DIR" tmux -L standin -f /dev/null "$@"; }
new_session() { without_bats_fds env TMUX_TMPDIR="$TMUX_DIR" tmux -L standin -f /dev/null new-session -d -s "$@" >"$W/tmux.log" 2>&1; }
pane_shows() { tm capture-pane -p -t "=$1:" | grep -q -- "$2"; }

real_firefox() {
  local f
  for f in /Applications/Firefox.app/Contents/MacOS/firefox "$(command -v firefox 2>/dev/null)"; do
    [ -x "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

# bats test_tags=feature:evaluator-tools,standin:firefox
@test "the real Firefox writes prefs.js into a fresh profile, stays running and ends on TERM" {
  local ff
  ff="$(real_firefox)" || skip "firefox missing"
  mkdir -p "$W/prof"
  printf '<!doctype html><title>stand-in check</title>' >"$W/page.html"
  without_bats_fds bash -c 'MOZ_HEADLESS=1 "$1" -new-instance -profile "$2" -new-window "$3" >"$4" 2>&1 & echo $! >"$5"' _ \
    "$ff" "$W/prof" "$W/page.html" "$W/ff.log" "$W/ff.pid"
  FF_PID="$(cat "$W/ff.pid")"
  wait_until 60 test -e "$W/prof/prefs.js"
  kill -0 "$FF_PID"
  run ps -o command= -p "$FF_PID"
  assert_output --partial "-profile $W/prof"
  kill "$FF_PID"
  wait_until 20 bash -c '! kill -0 "$1" 2>/dev/null' _ "$FF_PID"
}

# bats test_tags=feature:evaluator-tools,standin:tmux
@test "the real tmux captures a pane's text with its colours" {
  own_tmux
  new_session col "printf '\\033[31mred words\\033[0m then plain\\n'; exec cat"
  wait_until 15 pane_shows col "then plain"
  run tm capture-pane -e -p -S - -t "=col:"
  assert_success
  assert_output --regexp "$(printf '\033')\[31mred words"
  assert_output --partial "then plain"
}

# bats test_tags=feature:evaluator-tools,standin:tmux
@test "the real tmux says no to has-session for a name that does not exist" {
  own_tmux
  new_session there "exec cat"
  run tm has-session -t "=there"
  assert_success
  run tm has-session -t "=not-there"
  assert_failure
}

# bats test_tags=feature:evaluator-tools,standin:open
@test "macOS: the real open fails with a message for a page that does not exist" {
  [ "$(uname -s)" = Darwin ] || skip "not macOS: only a Mac has open"
  run /usr/bin/open "$W/no-such-page.html"
  assert_failure
  assert_output --partial "does not exist"
}

# bats test_tags=feature:install,standin:defaults
@test "macOS: the real defaults reads, writes and deletes keys the way the stand-in does" {
  [ "$(uname -s)" = Darwin ] || skip "not macOS: only a Mac has defaults"
  DOMAIN="claude-config.test.$$.$RANDOM"
  # the same commands against the real tool and against the stand-in: the same output and exit status
  transcript() {
    local r
    local -a d=("$@")
    r=0; "${d[@]}" read "$DOMAIN" Folder 2>/dev/null || r=$?; echo "missing read: $r"
    "${d[@]}" write "$DOMAIN" Folder -string "/a b/c"; "${d[@]}" read "$DOMAIN" Folder
    "${d[@]}" write "$DOMAIN" Load -bool false; "${d[@]}" read "$DOMAIN" Load
    "${d[@]}" write "$DOMAIN" Load -bool true; "${d[@]}" read "$DOMAIN" Load
    r=0; "${d[@]}" delete "$DOMAIN" Folder >/dev/null 2>&1 || r=$?; echo "delete: $r"
    r=0; "${d[@]}" delete "$DOMAIN" Folder >/dev/null 2>&1 || r=$?; echo "second delete: $r"
  }
  real="$(transcript /usr/bin/defaults)"
  fake="$(transcript bash "$REPO/test/fixtures/install/defaults")"
  assert_equal "$fake" "$real"
}

# bats test_tags=feature:run-agent,standin:claude-cli
@test "the real claude knows every option a launch passes to it" {
  local claude
  claude="$(PATH="$PATH:$REAL_HOME/.local/bin" command -v claude)" || skip "claude missing"
  run "$claude" --help
  assert_success
  local flag
  for flag in --agent --name --model --effort --permission-mode --continue --resume; do
    printf '%s\n' "$output" | grep -qE -- "(^|[ ,])$flag([ ,=<[]|\$)" || { echo "claude --help lacks $flag"; false; }
  done
}

# bats test_tags=feature:run-agent,standin:claude-cli
@test "the real claude exits with an error for an option it does not know" {
  local claude
  claude="$(PATH="$PATH:$REAL_HOME/.local/bin" command -v claude)" || skip "claude missing"
  run "$claude" --no-such-option-zork -p x
  assert_failure
  assert_output --partial "no-such-option-zork"
}

# bats test_tags=feature:restore-sessions,standin:restore-tmux
@test "the real tmux answers the pane questions restore-sessions asks" {
  own_tmux
  new_session work "exec cat"
  export LC_ALL=C
  run tm -u list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_id}	#{pane_current_command}	#{pane_pid}'
  assert_success
  assert_a_line_matches '^work	[0-9]+	[0-9]+	%[0-9]+	cat	[0-9]+$'
  local id
  id="$(printf '%s\n' "$output" | cut -f4)"
  run tm show -gv base-index
  assert_success
  assert_output --regexp '^[0-9]+$'
  run tm display -p -t "$id" '#{alternate_on}'
  assert_output "0"
  run tm capture-pane -p -t "%999"
  assert_failure
}

# bats test_tags=feature:restore-sessions,standin:restore-ps
@test "the real ps and pgrep list processes the way restore-sessions reads them" {
  [ "$(uname -s)" = Linux ] || skip "not Linux: restore-sessions runs in WSL and uses GNU ps and pgrep"
  command -v pgrep >/dev/null 2>&1 || skip "pgrep missing"
  without_bats_fds bash -c 'bash -c "sleep_for() { read -t 60 <>/dev/udp/127.0.0.1/9; }; sleep_for" standin-marker & echo $! >"$1"; wait' _ "$W/pid" >/dev/null 2>&1 &
  wait_until 10 test -s "$W/pid"
  FF_PID="$(cat "$W/pid")"
  run pgrep -af standin-marker
  assert_success
  assert_a_line_matches "^$FF_PID .*standin-marker"
  run ps -o args= --ppid "$(ps -o ppid= -p "$FF_PID" | tr -d ' ')"
  assert_success
  assert_output --partial "standin-marker"
}

# bats test_tags=feature:restore-sessions,standin:journalctl
@test "stop-time.sh reads the real journalctl or says why it cannot" {
  command -v journalctl >/dev/null 2>&1 || skip "journalctl missing"
  run bash "$REPO/skills/restore-sessions/scripts/stop-time.sh"
  if [ "$status" = 0 ]; then
    assert_a_line_matches '^stop	[A-Z][a-z][a-z] [0-9-]+ [0-9:]+ [A-Z]+$'
  else
    assert_output --regexp '^no stop time: (no previous boot|journalctl --list-boots failed)'
  fi
}

# bats test_tags=feature:restore-sessions,standin:gnu-date
@test "GNU date and touch read the times the restore-sessions stand-ins read" {
  date --version >/dev/null 2>&1 || skip "GNU date missing"
  run env TZ=America/New_York date -d "2026-10-15 04:56:11" '+%a %Y-%m-%d %H:%M:%S %Z'
  assert_output "Thu 2026-10-15 04:56:11 EDT"
  run env TZ=America/New_York date -d "Thu 2026-10-15 04:56:11 EDT" +%s
  assert_output "1792054571"
  touch -d "2026-10-15T04:56:11-04:00" "$W/stamped"
  run date -r "$W/stamped" +%s
  assert_output "1792054571"
}

# bats test_tags=feature:test-speedup,standin:maven
@test "baseline reads the count and slowest times from a real Maven run" {
  command -v mvn >/dev/null 2>&1 || skip "mvn missing"
  command -v java >/dev/null 2>&1 || skip "java missing"
  command -v javac >/dev/null 2>&1 || skip "javac missing"
  mkdir -p "$W/proj/src/test/java"
  cd "$W/proj"
  cat >pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion><groupId>t</groupId><artifactId>t</artifactId><version>1</version>
  <properties><maven.compiler.release>17</maven.compiler.release><project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
  <dependencies><dependency><groupId>org.junit.jupiter</groupId><artifactId>junit-jupiter</artifactId><version>5.11.4</version><scope>test</scope></dependency></dependencies>
  <build><plugins><plugin><artifactId>maven-compiler-plugin</artifactId><version>3.13.0</version></plugin><plugin><artifactId>maven-surefire-plugin</artifactId><version>3.5.2</version></plugin></plugins></build>
</project>
XML
  cat >src/test/java/ATest.java <<'JAVA'
import org.junit.jupiter.api.Test;
class ATest {
  @Test void quick() {}
  @Test void slow() throws Exception { Thread.sleep(1200); }
}
JAVA
  export MAVEN_OPTS="-Dmaven.repo.local=$W/m2" TMPDIR="$W"
  run bash "$REPO/skills/test-speedup/scripts/measure.sh" baseline 1
  assert_success
  assert_output --partial "RUNNER=maven"
  assert_output --partial "COUNT=2"
  assert_equal "$(printf '%s\n' "$output" | sed -n '/^SLOWEST/,/^DONE/p' | sed -n '2s/^[0-9.]*	//p')" "slow"
}

# bats test_tags=feature:test-speedup,standin:rspec
@test "baseline reads the count and slowest examples from a real RSpec run" {
  command -v bundle >/dev/null 2>&1 || skip "bundle missing"
  mkdir -p "$W/proj/spec"
  cd "$W/proj"
  printf 'gem "rspec"\n' >Gemfile
  printf 'RSpec.describe "cart" do\n  it("adds") { expect(1).to eq(1) }\n  it("empties") { expect([]).to be_empty }\nend\n' >spec/cart_spec.rb
  TMPDIR="$W" bundle exec rspec --version >/dev/null 2>&1 || skip "rspec gem missing"
  TMPDIR="$W" run bash "$REPO/skills/test-speedup/scripts/measure.sh" baseline 1
  assert_success
  assert_output --partial "COUNT=2"
  assert_output --partial "slowest examples"
}

# bats test_tags=feature:test-speedup,standin:pytest
@test "baseline reads the count of every outcome from a real pytest run" {
  local real=()
  if command -v pytest >/dev/null 2>&1; then real=("$(command -v pytest)")
  else
    local uv
    uv="$(PATH="$PATH:$REAL_HOME/.local/bin" command -v uv)" || skip "pytest missing"
    real=(env "UV_CACHE_DIR=$(HOME="$REAL_HOME" "$uv" cache dir)" "$uv" run --quiet --no-project --with pytest pytest)
  fi
  mkdir -p "$W/proj" "$W/bin"
  printf '#!/usr/bin/env bash\nexec%s "$@"\n' "$(printf ' %q' "${real[@]}")" >"$W/bin/pytest"
  chmod +x "$W/bin/pytest"
  cd "$W/proj"
  touch pyproject.toml
  cat >test_cart.py <<'PY'
import pytest
@pytest.mark.parametrize("n", [1, 2, 3])
def test_adds(n): assert n
@pytest.mark.parametrize("n", [1, 2])
def test_empties(n): assert 0
@pytest.mark.skip
def test_later(): pass
@pytest.mark.xfail
def test_known(): assert 0
PY
  PATH="$W/bin:$PATH" TMPDIR="$W" run bash "$REPO/skills/test-speedup/scripts/measure.sh" baseline 1
  assert_failure 1
  assert_a_line_matches '^RUNNER=pytest$'
  assert_a_line_matches '^COUNT=7$'
}
