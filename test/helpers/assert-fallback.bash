# Used only while test/vendor/bats-support, bats-assert and bats-file are absent (test/helpers/common.bash).
# The subset of their assertions the tests call, with the same names and arguments. Each prints what it saw
# on failure. Delete this file once the submodules are in.
_show() { printf '%s\n' "-- $1 --" "status: ${status:-}" "output:" "${output:-}" >&2; return 1; }
assert_success() { [ "${status:-1}" -eq 0 ] || _show "wanted exit 0"; }
assert_failure() {
  if [ $# -gt 0 ]; then [ "${status:-0}" -eq "$1" ] || _show "wanted exit $1"
  else [ "${status:-0}" -ne 0 ] || _show "wanted a non-zero exit"; fi
}
assert_equal() { [ "$1" = "$2" ] || { printf '%s\n' "-- values differ --" "got:    $1" "wanted: $2" >&2; return 1; }; }
# assert_output [--partial|--regexp] <text>
assert_output() {
  case "${1:-}" in
    --partial) case "$output" in *"$2"*) ;; *) _show "output lacks: $2" ;; esac ;;
    --regexp)  printf '%s\n' "$output" | grep -Eq -- "$2" || _show "no output line matches: $2" ;;
    *)         [ "$output" = "${1:-}" ] || _show "output is not: ${1:-}" ;;
  esac
}
refute_output() {
  case "${1:-}" in
    --partial) case "$output" in *"$2"*) _show "output holds: $2" ;; esac ;;
    --regexp)  if printf '%s\n' "$output" | grep -Eq -- "$2"; then _show "an output line matches: $2"; fi ;;
    *)         [ -z "$output" ] || _show "wanted no output" ;;
  esac
}
assert_file_exist()     { [ -e "$1" ] || { echo "no such file: $1" >&2; return 1; }; }
assert_file_not_exist() { [ ! -e "$1" ] || { echo "file exists: $1" >&2; return 1; }; }
# assert_line <text>: one whole line of the output is <text>
assert_line() { printf '%s\n' "$output" | grep -Fxq -- "$1" || _show "no output line is: $1"; }
