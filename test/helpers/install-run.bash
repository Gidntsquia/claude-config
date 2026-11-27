#!/bin/bash
# usage: SCN_REAL_HOME=<home> SCN_OUT=<dir> install-run.bash <scenario>
# Runs one install scenario in its own process (install-bats.bash starts it; on macOS through test/helpers/stock-mac.sh).
# Writes into SCN_OUT: checks (one ok/FAIL line per check), homes (the throwaway homes), skip (why nothing was run),
# done (the scenario returned). Exit 0 with no failed check, 1 with one, 2 for a refused run.
# SCN_TERMFLAG=--terminal|--no-terminal overrides the flag; SCN_NEED_OLDTAG=1 (CI): a clone without the old tags
# and history is a failure, not a skip; SCN_NO_PLIST_STEP=1: leave UPDATING.md's copy-the-plist step out of plist
# (its red run); SCN_NO_KEYCHAIN=1: make the home without a keychain (the red run for the keychain guard).
set -u
name="${1:?scenario name}"
REAL_HOME="${SCN_REAL_HOME:?}"; TERMFLAG="${SCN_TERMFLAG:-}"
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$D/install-lib.bash"
. "$D/install-dirty.bash"
. "$D/install-scn.bash"

skipped() { echo "skip $name: $1"; [ -z "${SCN_OUT:-}" ] || printf '%s\n' "$1" > "$SCN_OUT/skip"; }
needs_links() { if can_link; then return 0; fi; skipped "this account cannot make symlinks, so $1"; return 1; }
has_ref() { git -C "$R" rev-parse -q --verify "$1^{commit}" >/dev/null 2>&1; }
# The scenarios that start from an older commit need this clone's history and tags.
old_history() {  # <ref...>
  local ref
  for ref in "$@"; do
    has_ref "$ref" && continue
    if [ -n "${SCN_NEED_OLDTAG:-}" ]; then bad "$name: $R lacks $ref (a shallow or tagless checkout; fetch with full history and tags)"
    else skipped "the clone lacks $ref (not a git checkout, or fetched without tags)"; fi
    return 1
  done
}

# A tmux folder of this run's own: --check starts and kills a server on a fixed socket name, so two scenarios
# running at once would otherwise kill each other's.
TMUX_TMPDIR="$(mktemp -d /tmp/cc-tmux.XXXXXX)" || exit 2
export TMUX_TMPDIR
unset TMUX TMUX_PANE
kc_begin
case "$name" in
  a|b) scenario "$name" ;;
  theirs|odd|noguard|nohook|windows) run_in "$name" "scn_$name" ;;
  sep22|moved) if needs_links "the older layouts cannot be built"; then run_in "$name" "scn_$name"; fi ;;
  assistant) if needs_links "a project cannot link the agent"; then run_in assistant scn_assistant; fi ;;
  stock) if on_win_host; then skipped "the stock PATH is a macOS/Linux case"; else run_in stock scn_stock; fi ;;
  # Not on a real Windows host: a pretend wsl/mac install there splits env.CLAUDE_CODE_PLUGIN_DIRS on ":" while its
  # paths hold "C:", so --check fails on a line that has nothing to do with the tools.
  oswsl|osmac) if on_win_host; then skipped "a pretend WSL or Mac install cannot pass --check on a real Windows host"
    elif needs_links "the linked set cannot be read"; then run_in "$name" "scn_$name"; fi ;;
  oldtag) if on_win_host; then skipped "v1.2.1's install.sh was never run on Windows without WSL"
    elif old_history refs/tags/v1.2.1; then run_in oldtag scn_oldtag; fi ;;
  plist|dirty-v121|dirty-beta5)
    if on_win_host; then skipped "the older installers were never run on Windows without WSL"
    elif old_history refs/tags/v1.2.1 refs/tags/v1.3.0-beta.5 "$SEP_COMMIT"; then
      case "$name" in
        plist) run_in plist scn_plist ;;
        dirty-v121) run_in dirty scn_dirty_v121 ;;
        dirty-beta5) run_in dirty scn_dirty_beta5 ;;
      esac
    fi ;;
  # Scenario a again, in its own process, with the keychain left out of the home. It must stop at keychain_ready:
  # exit 1, a FAIL line naming the home, and neither install.sh nor claude started.
  nokeychain)
    if [ "$(uname -s)" != Darwin ]; then skipped "keychains are a macOS case"
    else
      echo "== scenario nokeychain (scenario a in a home with no Library/Keychains)"
      out="$(SCN_OUT= SCN_NO_KEYCHAIN=1 bash "${BASH_SOURCE[0]}" a 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
      expect "nokeychain: the run fails (exit $rc)" test "$rc" = 1
      expect "nokeychain: the FAIL line names the home" has "$out" '^FAIL a: the throwaway home /.*cc-install-a\.[A-Za-z0-9]* has no Library/Keychains'
      expect "nokeychain: neither install.sh nor claude ran in it" sh -c '! printf "%s\n" "$1" | grep -q -e "installing claude-config" -e "claude doctor" -e "^ok   a:"' _ "$out"
    fi ;;
  *) bad "unknown scenario: $name" ;;
esac
kc_end
rm -rf "$TMUX_TMPDIR"
[ -z "${SCN_OUT:-}" ] || : > "$SCN_OUT/done"
exit $(( fails > 0 ))
