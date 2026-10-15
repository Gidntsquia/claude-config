#!/usr/bin/env bash
# usage: apply.sh DIR
# Runs DIR/ops.tsv from plan.sh: creates missing tmux sessions/windows, splits new panes (never moves a pane out
# of its window, never closes anything), starts one terminal-pet per window in its top-left pane, sends exactly one
# line `cd '<cwd>' && claude --resume <id>` + Enter to each session's pane, and opens a Windows Terminal window
# for each new tmux session (brought to front with win.sh; "in the taskbar" if that fails).
# Writes DIR/actions.log (every tmux/wt command, ET times), DIR/panes-final.tsv (key pane_id target) and
# DIR/wt.tsv (session title hwnd status) and DIR/sent-<pane>.txt (the pane's shell screen right after the resume line). RS_TMUX_L=<name> uses tmux -L <name> (tests); RS_NO_WT=1 skips wt.exe.
# New windows use the Windows Terminal profile $RS_WT_PROFILE (default Ubuntu) so they get its font and colors;
# without -p, wt.exe gives a bare command line the base settings (no Nerd Font: icons show as blanks).
set -uo pipefail
dir="${1:?usage: apply.sh DIR}"
ops="$dir/ops.tsv"; [ -f "$ops" ] || { echo "apply.sh: no $ops (run plan.sh first)" >&2; exit 2; }
log="$dir/actions.log"; : > "$log"
L=(); [ -n "${RS_TMUX_L:-}" ] && L=(-L "$RS_TMUX_L")
tm() { printf '%s tmux %s\n' "$(date '+%H:%M:%S %Z')" "${L[*]} $*" >> "$log"; tmux "${L[@]}" "$@"; }
WIN="$HOME/.claude/local-tools/win.sh"
WTP="${RS_WT_PROFILE:-Ubuntu}"
WT="$(command -v wt.exe || echo /mnt/c/Users/Jaxon/AppData/Local/Microsoft/WindowsApps/wt.exe)"
PET="$(command -v terminal-pet || echo "$HOME/.cargo/bin/terminal-pet")"
declare -A key win   # plan key -> pane id; "S:W" -> window id
: > "$dir/wt.tsv"; warn=()

wid() {  # S:W -> window id (resolved once)
  [ -n "${win[$1]:-}" ] || win[$1]=$(tm display -p -t "$1" '#{window_id}' 2>/dev/null)
  printf '%s' "${win[$1]:-}"
}
pid_of() {  # plan key -> pane id (existing panes use their %id as key)
  case "$1" in new:*) printf '%s' "${key[$1]:-}" ;; *) printf '%s' "$1" ;; esac
}
ready() {  # wait (max 5 s) until a pane's shell has drawn its prompt, so typed keys are not echoed early
  for _ in $(seq 1 25); do [ -n "$(tmux "${L[@]}" capture-pane -p -t "$1" 2>/dev/null | tr -d '[:space:]')" ] && return; sleep 0.2; done
}
hwnds() { [ -x "$WIN" ] && "$WIN" find "$1" 2>&1 | awk '$1 ~ /^[0-9]+$/ && !/ windows? match/ { print $1 }'; }   # every window titled $1
last_pane() { tm list-panes -t "$1" -F '#{pane_index} #{pane_id}' | sort -n | tail -1 | cut -d' ' -f2; }

while IFS=$'\t' read -r op a b c d; do
  case "$op" in
    new-session)
      if tm has-session -t "=$a" 2>/dev/null; then warn+=("tmux session $a appeared meanwhile; kept it"); continue; fi
      tm new-session -d -s "$a" -c "$HOME" -x 200 -y 50 || { warn+=("new-session $a failed"); continue; }
      win["$a:$b"]=$(tm display -p -t "=$a:" '#{window_id}') ;;
    new-window)
      w=$(tm new-window -d -t "=$a:" -c "$HOME" -P -F '#{window_index} #{window_id}') || { warn+=("new-window in $a failed"); continue; }
      win["$a:$b"]=${w#* }
      [ "${w%% *}" = "$b" ] || warn+=("window $a:$b was created as $a:${w%% *}") ;;
    first-pane)
      key[$b]=$(tm list-panes -t "$(wid "$a")" -F '#{pane_index} #{pane_id}' | sort -n | head -1 | cut -d' ' -f2) ;;
    split)
      w=$(wid "$a"); p=$(tm split-window -d -t "$(last_pane "$w")" -c "$HOME" -P -F '#{pane_id}' 2>>"$log")
      if [ -z "$p" ]; then   # no space: re-tile and split the biggest pane
        tm select-layout -t "$w" tiled >/dev/null
        big=$(tm list-panes -t "$w" -F '#{e|*:#{pane_width},#{pane_height}} #{pane_id}' | sort -n | tail -1 | cut -d' ' -f2)
        p=$(tm split-window -d -t "$big" -c "$HOME" -P -F '#{pane_id}') || { warn+=("split in $a failed"); continue; }
      fi
      key[$b]=$p; tm select-layout -t "$w" tiled >/dev/null ;;
    swap)
      tm swap-pane -d -s "$(pid_of "$b")" -t "$(pid_of "$c")" ;;
    layout)
      tm select-layout -t "$(wid "$a")" tiled >/dev/null ;;
    pet)
      p=$(pid_of "$b")
      if [ ! -x "$PET" ]; then warn+=("terminal-pet not found; no pet in $a"); continue; fi
      if [ "$c" = squid ]; then cmd="cd ~ && terminal-pet"; else cmd="cd ~ && terminal-pet --pet $c"; fi
      ready "$p"; tm send-keys -t "$p" "$cmd" Enter ;;
    resume)
      p=$(pid_of "$b"); q=${c//\'/\'\\\'\'}; ready "$p"
      tm send-keys -t "$p" "cd '$q' && claude --resume $d" Enter
      # Save the shell screen showing the typed line now: a later resize (Windows Terminal attaching) can cut it
      # on tmux's saved screen once Claude has switched to the alternate screen.
      for _ in $(seq 1 20); do
        sc=$(tmux "${L[@]}" capture-pane -p -J -t "$p" 2>/dev/null)
        [ "$(tmux "${L[@]}" display -p -t "$p" '#{alternate_on}' 2>/dev/null)" = 1 ] && sc=$(tmux "${L[@]}" capture-pane -a -p -J -t "$p" 2>/dev/null)
        grep -qF "claude --resume $d" <<<"$sc" && break; sleep 0.1
      done
      printf '%s\n' "$sc" > "$dir/sent-${p#%}.txt" ;;
    wt)
      t="tmux $a (restored)"
      old_h=" $(hwnds "$t" | tr '\n' ' ') "   # windows with this title from an earlier run are not ours
      if [ -n "${RS_NO_WT:-}" ]; then printf '%s\t%s\t\tskipped (RS_NO_WT)\n' "$a" "$t" >> "$dir/wt.tsv"; continue; fi
      printf '%s wt.exe -w new -p "%s" --title "%s" --suppressApplicationTitle wsl.exe -d %s -- tmux %s attach -t %s\n' \
        "$(date '+%H:%M:%S %Z')" "$WTP" "$t" "${WSL_DISTRO_NAME:-Ubuntu}" "${L[*]}" "$a" >> "$log"
      "$WT" -w new -p "$WTP" --title "$t" --suppressApplicationTitle \
        wsl.exe -d "${WSL_DISTRO_NAME:-Ubuntu}" -- tmux "${L[@]}" attach -t "=$a" >/dev/null 2>&1
      for _ in $(seq 1 30); do [ -n "$(tmux "${L[@]}" list-clients -t "=$a" 2>/dev/null)" ] && break; sleep 0.5; done
      attached=$([ -n "$(tmux "${L[@]}" list-clients -t "=$a" 2>/dev/null)" ] && echo yes || echo no)
      status="in the taskbar (win.sh could not bring it to front)"; hwnd=""
      if [ -x "$WIN" ]; then
        for _ in $(seq 1 20); do
          hwnd=$(hwnds "$t" | while read -r h; do [[ "$old_h" == *" $h "* ]] || echo "$h"; done | head -1)
          [ -n "$hwnd" ] && break; sleep 0.5
        done
        if [ -n "$hwnd" ] && "$WIN" reg "$hwnd" "$t" >/dev/null 2>&1 && "$WIN" front "$hwnd" >/dev/null 2>&1; then
          status="frontmost"
        fi
      fi
      printf '%s\t%s\t%s\t%s (attached: %s)\n' "$a" "$t" "$hwnd" "$status" "$attached" >> "$dir/wt.tsv" ;;
    "") ;;
    *) warn+=("unknown op: $op") ;;
  esac
done < "$ops"

# Where every planned pane ended up.
: > "$dir/panes-final.tsv"
while IFS=$'\t' read -r tgt role how k rest; do
  p=$(pid_of "$k"); now=$(tmux "${L[@]}" display -p -t "$p" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null)
  printf '%s\t%s\t%s\t%s\n' "$k" "$p" "${now:-gone}" "$tgt" >> "$dir/panes-final.tsv"
done < "$dir/plan.tsv"
echo "applied $(grep -c . "$ops") steps; log: $log"
cat "$dir/wt.tsv" | sed 's/^/window: /'
for w in "${warn[@]+"${warn[@]}"}"; do echo "WARNING: $w"; done
exit 0
