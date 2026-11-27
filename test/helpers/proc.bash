# without_bats_fds <command...>: run a command that may leave a process running (a tmux server, a fake claude
# that stays alive) with every file descriptor above 2 closed. bats waits for its own pipes to close, so one
# orphan holding one of them stalls the whole suite until it exits. Redirect stdout and stderr to a file too.
# Whatever a test starts, the same test kills in teardown().
without_bats_fds() {
  (
    for _fd in 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do eval "exec $_fd>&-"; done
    "$@"
  )
}
