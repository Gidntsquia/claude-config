# Line-by-line matching of $output. bats-assert's `--regexp` matches the output as one string (^ and $ are its
# ends), so a pattern about one line goes through these.
assert_a_line_matches() {
  printf '%s\n' "${output:-}" | grep -Eq -- "$1" && return 0
  printf '%s\n' "-- no output line matches: $1 --" "output:" "${output:-}" >&2; return 1
}
refute_a_line_matches() {
  printf '%s\n' "${output:-}" | grep -Eq -- "$1" || return 0
  printf '%s\n' "-- an output line matches: $1 --" "output:" "${output:-}" >&2; return 1
}
