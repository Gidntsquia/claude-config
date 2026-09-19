#!/usr/bin/env bash
# Claude Code statusline, gruvbox-dark themed to match ~/.config/starship.toml
input=$(cat)

ORANGE='48;2;214;93;14'
YELLOW='48;2;215;153;33'
AQUA='48;2;104;157;106'
BLUE='48;2;69;133;136'
RED='48;2;204;36;29'
PURPLE='48;2;177;98;134'
GREEN='48;2;152;151;26'
STEEL='48;2;107;114;128'
SLATE='48;2;53;72;97'
SLATE_FG='38;2;245;249;255'
COBALT='48;2;49;110;196'
FG='38;2;251;241;199'

esc() { printf '\033[%sm' "$1"; }
rst() { printf '\033[0m'; }

# model name -> (bg color code, fg escape for the next separator, text fg)
model_color() {
  case "$1" in
    *Opus*)   echo "$SLATE 38;2;53;72;97 $SLATE_FG" ;;
    *Sonnet*) echo "$STEEL 38;2;107;114;128 $FG" ;;
    *Haiku*)  echo "$GREEN 38;2;152;151;26 $FG" ;;
    *Fable*)  echo "$COBALT 38;2;49;110;196 $FG" ;;
    *)        echo "$YELLOW 38;2;215;153;33 $FG" ;;
  esac
}

# drop the version number when it's the current default for that family
strip_default_version() {
  case "$1" in
    "Opus 5")     echo "Opus" ;;
    "Sonnet 5")   echo "Sonnet" ;;
    "Haiku 4.5")  echo "Haiku" ;;
    "Fable 5.1")  echo "Fable" ;;
    *)            echo "$1" ;;
  esac
}

# reasoning effort -> a small visual gauge instead of a word
effort_icon() {
  case "$1" in
    low)    echo "○" ;;
    medium) echo "◔" ;;
    high)   echo "◑" ;;
    xhigh)  echo "◕" ;;
    max)    echo "●" ;;
    *)      echo "" ;;
  esac
}

if [ "${CLAUDE_STATUSLINE_NF:-0}" = "1" ]; then
  SEP=""
else
  SEP="|"
fi

model=$(echo "$input" | jq -r '.model.display_name // "?"')
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')

# rate_limits are absent until the first API response of a session; fall back
# to the last values we saw so 5h/7d don't disappear on a fresh prompt.
CACHE="${TMPDIR:-/tmp}/claude-statusline-usage.cache"
if [ -n "$five_pct" ] && [ "$five_pct" != "null" ]; then
  printf '%s %s\n' "$five_pct" "${week_pct:-}" > "$CACHE" 2>/dev/null
elif [ -f "$CACHE" ]; then
  read -r cached_five cached_week < "$CACHE"
  five_pct="$cached_five"
  [ -z "$week_pct" ] && week_pct="$cached_week"
fi

short_cwd=$(basename "${project_dir:-$cwd}")
[ -z "$short_cwd" ] && short_cwd="/"

# easter eggs: one stable roll per session, weighted so ~93% of sessions
# see nothing. roll is derived from session_id so it doesn't flicker
# between prompts within the same session.

# bumps a per-session, per-story counter file and echoes the new count
saga_tick() {
  f="${TMPDIR:-/tmp}/claude-statusline-$1-${session_id:-$$}.count"
  n=0
  [ -f "$f" ] && n=$(cat "$f" 2>/dev/null)
  n=$((n + 1))
  printf '%s' "$n" > "$f" 2>/dev/null
  echo "$n"
}

squid="🦑"
seed="${session_id:-$$-$cwd}"
roll=$(printf '%s' "$seed" | cksum | awk '{print $1 % 10000}')
if   [ "$roll" -lt 2 ];    then squid="✨🦑✨"     # golden squid, the rarest of all (0.02%)
elif [ "$roll" -lt 15 ];   then squid="🐉"        # legendary: dragon squid (0.13%)
elif [ "$roll" -lt 30 ];   then squid="🦑🦄"       # narwhal squid (0.15%)
elif [ "$roll" -lt 55 ];   then
  # the egg hatches after enough prompts in the same session
  n=$(saga_tick hatch)
  if [ "$n" -ge 6 ]; then
    squid="🦑🦑🦑"      # the egg hatched: squid triple
  else
    squid="🦑🥚🦑"      # squid pair minding an egg (0.25%)
  fi
elif [ "$roll" -lt 85 ];   then
  # tortoise and hare: hare sprints out, stalls, tortoise grinds it out
  n=$(saga_tick race)
  case "$n" in
    1)       squid="🐇╌╌╌╌╌🐢╌╌🏁" ;;  # hare bolts to an early lead
    2)       squid="🐇╌╌╌╌🐢╌╌╌🏁" ;;
    3)       squid="🐇╌╌╌🐢╌╌╌╌🏁" ;;
    4)       squid="🐇╌╌🐢╌╌╌╌╌🏁" ;;
    5)       squid="🐇╌🐢╌╌╌╌╌╌🏁" ;;
    6)       squid="🐇🐢╌╌╌╌╌╌╌🏁" ;;  # tortoise finally catches up
    7)       squid="🐢🐇╌╌╌╌╌╌╌🏁" ;;  # and passes
    *)       squid="🏆🐢╌╌╌╌╌╌😴🐇" ;; # tortoise wins, hare's still napping (0.3%)
  esac
elif [ "$roll" -lt 110 ];  then
  # a seed slowly grows into a fruit-bearing tree
  n=$(saga_tick tree)
  case "$n" in
    1)       squid="🌱" ;;
    2)       squid="🌿" ;;
    3)       squid="🌳" ;;
    *)       squid="🌳🍎" ;;            # bears fruit (0.25%)
  esac
elif [ "$roll" -lt 135 ];  then
  # a caterpillar becomes a butterfly
  n=$(saga_tick butterfly)
  case "$n" in
    1)       squid="🐛" ;;
    2)       squid="🐛💤" ;;
    3)       squid="🟤" ;;
    *)       squid="🦋" ;;              # emerges (0.25%)
  esac
elif [ "$roll" -lt 160 ];  then squid="👻🦑"       # ghost squid (0.25%)
elif [ "$roll" -lt 185 ];  then squid="🦈🦑"       # shark on the chase (0.25%)
elif [ "$roll" -lt 215 ];  then squid="🦑🐢"       # squid + turtle friend (0.3%)
elif [ "$roll" -lt 245 ];  then squid="🦑🐇"       # squid + rabbit friend (0.3%)
elif [ "$roll" -lt 275 ];  then squid="🦑🦑"       # squid found its twin (0.3%)
elif [ "$roll" -lt 355 ];  then squid="🦀"        # crabby impostor (0.8%)
elif [ "$roll" -lt 455 ];  then squid="🫧"        # just bubbles, squid's hiding (1%)
elif [ "$roll" -lt 575 ];  then squid="🐙"        # octopus impostor (1.2%)
elif [ "$roll" -lt 725 ];  then squid="🐊"        # alligator swapped in (1.5%)
elif [ "$roll" -lt 755 ];  then
  # Humpty Dumpty
  n=$(saga_tick humpty)
  case "$n" in
    1)       squid="🥚🧱" ;;             # sitting on the wall
    2)       squid="🥚💥🧱" ;;           # the great fall
    *)
      if [ $((roll % 2)) -eq 0 ]; then
        squid="🍳"        # couldn't be put together again
      else
        squid="🥚✨"      # all the king's horses pulled it off
      fi
      ;;
  esac
elif [ "$roll" -lt 785 ];  then
  # Little Red Riding Hood
  n=$(saga_tick redhood)
  case "$n" in
    1)       squid="🧒🔴🌲" ;;           # walking through the woods
    2)       squid="🐺👀" ;;             # the wolf appears
    *)
      if [ $((roll % 2)) -eq 0 ]; then
        squid="🪓🐺"      # the woodsman saves the day
      else
        squid="😈🐺"      # the wolf wins
      fi
      ;;
  esac
elif [ "$roll" -lt 815 ];  then
  # squid robs a bank
  n=$(saga_tick heist)
  case "$n" in
    1)       squid="🦑🎭" ;;             # dons a mask
    2)       squid="🦑💰🏦" ;;           # inside the vault
    *)
      if [ $((roll % 2)) -eq 0 ]; then
        squid="🚔🦑" # caught red-handed
      else
        squid="🦑💰🏝️" # gets away with it
      fi
      ;;
  esac
elif [ "$roll" -lt 845 ];  then
  # the three little pigs
  n=$(saga_tick pigs)
  case "$n" in
    1)       squid="🐷🏠" ;;             # the straw house
    2)       squid="🐺💨🏠" ;;           # the wolf huffs and puffs
    *)
      if [ $((roll % 2)) -eq 0 ]; then
        squid="🐺🍲" # the wolf ends up in the pot
      else
        squid="🐷😱🐺" # the house comes down
      fi
      ;;
  esac
elif [ "$roll" -lt 880 ];  then
  # pokemon battle, squid included
  n=$(saga_tick pokebattle)
  case "$n" in
    1)       squid="🦑⚡" ;;             # battle starts
    2)       squid="🦑💥" ;;             # attacks clash
    *)
      if [ $((roll % 2)) -eq 0 ]; then
        squid="🦑🏆" # squid wins
      else
        squid="🦑😵" # squid faints
      fi
      ;;
  esac
elif [ "$roll" -lt 915 ];  then
  # Jack and the beanstalk
  n=$(saga_tick beanstalk)
  case "$n" in
    1)       squid="🫘🌱" ;;             # plants the bean
    2)       squid="🌱🌿🌳" ;;           # it grows overnight
    3)       squid="🧍🪜🌳" ;;           # Jack climbs up
    *)
      if [ $((roll % 2)) -eq 0 ]; then
        squid="🧍💰🪓🌳" # escapes with treasure, chops it down
      else
        squid="🗿🌳" # the giant catches him
      fi
      ;;
  esac
elif [ "$roll" -lt 945 ];  then
  # cooking meat
  n=$(saga_tick cookmeat)
  case "$n" in
    1)       squid="🥩" ;;               # raw
    2)       squid="🥩🔥" ;;             # on the fire
    3)       squid="🥩💨" ;;             # cooking through
    *)
      if [ $((roll % 2)) -eq 0 ]; then
        squid="🍖✅" # cooked to perfection
      else
        squid="🔥🍖⚫" # burnt to a crisp
      fi
      ;;
  esac
elif [ "$roll" -lt 1245 ]; then
  # common class: squid slowly eats a parcel of food, snack size varies the wait
  foodtype=$((roll % 4))
  case "$foodtype" in
    0) food="🍎"; done_at=3 ;;   # apple: quick snack
    1) food="🍕"; done_at=5 ;;   # pizza: medium
    2) food="🍰"; done_at=5 ;;   # cake: medium
    *) food="🍗"; done_at=7 ;;   # turkey leg: slow feast
  esac
  n=$(saga_tick food)
  if [ "$n" -gt "$done_at" ]; then
    squid="🦑"                  # back to normal, fully digested
  elif [ "$n" -eq "$done_at" ]; then
    squid="🦑😌"                # finished eating
  else
    dots=$(printf '.%.0s' $(seq 1 "$n"))
    squid="🦑${food}${dots}"    # nibbling away
  fi
fi

branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi
# keep long branch names from blowing out the line
if [ -n "$branch" ] && [ "${#branch}" -gt 20 ]; then
  branch="${branch:0:19}…"
fi

usage=""
if [ -n "$five_pct" ] && [ "$five_pct" != "null" ]; then
  usage=$(printf '5h %.0f%%' "$five_pct")
fi
# only show the weekly figure once it's worth worrying about
if [ -n "$week_pct" ] && [ "$week_pct" != "null" ] && awk "BEGIN{exit !($week_pct >= 70)}"; then
  weekfmt=$(printf '7d %.0f%%' "$week_pct")
  usage="${usage:+$usage }$weekfmt"
fi

usage_alert=0
if [ -n "$week_pct" ] && [ "$week_pct" != "null" ] && awk "BEGIN{exit !($week_pct >= 90)}"; then
  usage_alert=1
fi
if [ -n "$five_pct" ] && [ "$five_pct" != "null" ] && awk "BEGIN{exit !($five_pct >= 90)}"; then
  usage_alert=1
fi

# directory (orange)
out="$(esc "$ORANGE;$FG") $squid $short_cwd $(rst)"
prev_fg='38;2;214;93;14'

if [ -n "$branch" ]; then
  out+="$(esc "${prev_fg};${AQUA}")${SEP}$(rst)"
  out+="$(esc "$AQUA;$FG") $branch $(rst)"
  prev_fg='38;2;104;157;106'
fi

# model (color depends on model family)
read -r MODEL_BG model_next_fg MODEL_FG < <(model_color "$model")
model_label="$(strip_default_version "$model")"
if [ -n "$effort" ] && [ "$effort" != "null" ] && [ "$effort" != "medium" ]; then
  model_label="$model_label $(effort_icon "$effort")"
fi
out+="$(esc "${prev_fg};${MODEL_BG}")${SEP}$(rst)"
out+="$(esc "$MODEL_BG;$MODEL_FG") $model_label $(rst)"
prev_fg="$model_next_fg"

# usage limits (red if either is near the cap, else aqua)
if [ -n "$usage" ]; then
  if [ "$usage_alert" = "1" ]; then
    USAGE_BG="$RED"
    next_fg='38;2;204;36;29'
  else
    USAGE_BG="$AQUA"
    next_fg='38;2;104;157;106'
  fi
  out+="$(esc "${prev_fg};${USAGE_BG}")${SEP}$(rst)"
  out+="$(esc "$USAGE_BG;$FG") $usage $(rst)"
  prev_fg="$next_fg"
fi

out+="$(esc "${prev_fg}")${SEP}$(rst)"

printf '%s\n' "$out"
