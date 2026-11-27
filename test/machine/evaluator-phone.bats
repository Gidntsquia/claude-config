#!/usr/bin/env bats
# Phone-width pictures from the real Firefox, headless (no window opens). macOS with Firefox installed.

load ../helpers/common
load ../helpers/evaluator-tools

setup() {
  [ "$(uname -s)" = Darwin ] || skip "macOS only: elsewhere phone-shot.sh takes its picture with Node, not Firefox"
  [ -x /Applications/Firefox.app/Contents/MacOS/firefox ] || skip "Firefox is not installed in /Applications"
  evt_setup
  PH="$W/ph"; mkdir "$PH"
  export TMPDIR="$W/tmp"
  unset PHONE_FIREFOX_APP PHONE_PORT_WAIT PHONE_SETTLE_MS PHONE_OVERLAY_SCROLLBARS
}

teardown() {
  if [ -n "${TMUX_DIR:-}" ]; then
    TMUX_TMPDIR="$TMUX_DIR" tmux kill-server >/dev/null 2>&1
    rm -rf "$TMUX_DIR"
  fi
  evt_cleanup
}

none_running() { ! pgrep -f -- "$(evt_re "$W/tmp/phone-ff-")" >/dev/null; }
size() { python3 -c 'import struct,sys; b=open(sys.argv[1],"rb").read(24); print("%dx%d" % struct.unpack(">II", b[16:24]))' "$1"; }

# shoot <name> <kind> <source> [more]: take the picture; it succeeded, and its Firefox is gone afterwards
shoot() {
  local n="$1"; shift
  evo "$LT/common/phone-shot.sh" "$PH/$n" "$@"
  [ "$rc" = 0 ] || return 1
  wait_until 10 none_running || { echo "the headless Firefox is still running"; return 1; }
}

three_screens() {
  printf '<!doctype html><meta name="viewport" content="width=device-width"><style>html,body{margin:0}div{height:2300px;background:linear-gradient(#fff,#36c)}</style><div>three screens</div>' > "$PH/three.html"
}

# bats test_tags=feature:phone-pictures
@test "a page of three screens becomes three phone-width pictures and nothing else" {
  three_screens
  shoot 01-three html "$PH/three.html"
  assert_equal "$out" "png $PH/01-three-p1.png 780x1688
png $PH/01-three-p2.png 780x1688
png $PH/01-three-p3.png 780x1224"
  assert_equal "$(size "$PH/01-three-p1.png")" 780x1688
  assert_equal "$(size "$PH/01-three-p2.png")" 780x1688
  assert_equal "$(size "$PH/01-three-p3.png")" 780x1224
  assert_file_not_exist "$PH/01-three.png"
  run find "$PH" -name 'tmp-*'
  assert_output ""
}

# bats test_tags=feature:phone-pictures
@test "pictures stay 780 wide where the Mac always shows scroll bars" {
  three_screens
  export PHONE_OVERLAY_SCROLLBARS=0
  shoot 01b-bars html "$PH/three.html"
  has "$out" "png $PH/01b-bars-p3.png 780x1224"
}

# bats test_tags=feature:phone-pictures
@test "a short page becomes one picture no taller than a screen" {
  printf '<!doctype html><meta name="viewport" content="width=device-width"><p id="o"></p><script>document.getElementById("o").textContent=innerWidth+" "+devicePixelRatio+" "+matchMedia("(max-width:400px)").matches</script>' > "$PH/probe.html"
  shoot 02-short html "$PH/probe.html"
  has "$out" "png $PH/02-short.png 780x"
  h=${out##*x}
  [ "$h" -ge 240 ] && [ "$h" -le 1688 ]
}

# bats test_tags=feature:phone-pictures
@test "a Markdown file becomes a phone-width picture" {
  printf '# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- item\n' > "$PH/doc.md"
  shoot 03-md md "$PH/doc.md"
  has "$out" "png $PH/03-md.png 780x"
}

# bats test_tags=feature:phone-pictures
@test "a long text file is cut into phone screens" {
  seq 1 400 > "$PH/long.txt"
  shoot 04-text text "$PH/long.txt"
  has "$out" "png $PH/04-text-p1.png 780x1688"
}

# bats test_tags=feature:phone-pictures
@test "a range of lines of a text file becomes a picture" {
  seq 1 400 > "$PH/long.txt"
  shoot 05-range text "$PH/long.txt" 10-12
  has "$out" "png $PH/05-range.png 780x"
}

green_printed() { TMUX_TMPDIR="$TMUX_DIR" tmux capture-pane -p -t evt-phone | grep -qx 'green'; }

# bats test_tags=feature:phone-pictures
@test "a terminal session becomes a phone-width picture" {
  command -v tmux >/dev/null 2>&1 || skip "tmux is not installed"
  unset TMUX TMUX_PANE
  TMUX_DIR=$(mktemp -d /tmp/evt.XXXXXX)
  export TMUX_TMPDIR="$TMUX_DIR"
  EVT_PATH=$(dirname "$(command -v tmux)")
  without_bats_fds tmux -f /dev/null new-session -d -s evt-phone -x 100 -y 40 >/dev/null 2>&1
  tmux send-keys -t evt-phone "printf '\\033[32mgreen\\033[0m\\n'" Enter
  wait_until 20 green_printed
  shoot 06-tmux tmux evt-phone
  has "$out" "png $PH/06-tmux.png 780x"
}

# bats test_tags=feature:phone-pictures
@test "a web address becomes phone-width pictures" {
  three_screens
  shoot 07-url url "file://$PH/three.html"
  has "$out" "png $PH/07-url-p3.png 780x1224"
}

# bats test_tags=feature:phone-pictures
@test "an address that does not answer gives no picture and says why" {
  evo "$LT/common/phone-shot.sh" "$PH/08-bad" url "http://127.0.0.1:1/nothing"
  assert_equal "$rc" 1
  case "$(cat "$W/out" "$W/err")" in
    "phone-shot.sh: no picture: BiDi browsingContext.navigate: "*) ;;
    *) return 1;;
  esac
  run find "$PH" -name '08-*'
  assert_output ""
  wait_until 10 none_running
}
