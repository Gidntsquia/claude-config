# wait_until <seconds> <command...>: run the command every 0.1 s until it succeeds (return 0) or the deadline
# passes (return 1). The only place a test may wait; the lint in test/run refuses `sleep` everywhere else.
wait_until() {
  local limit="$1" end
  shift
  end=$(( $(date +%s) + limit ))
  while :; do
    "$@" >/dev/null 2>&1 && return 0
    [ "$(date +%s)" -ge "$end" ] && return 1
    sleep 0.1
  done
}
