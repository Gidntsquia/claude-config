#!/usr/bin/env bash
# Claude Code statusline, gruvbox-dark themed to match ~/.config/starship.toml

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

# Roll bands shared by every theme: band i covers rolls below BAND_HI[i]
# (and at or above BAND_HI[i-1]). Each theme fills the same band with its
# own egg, so the odds and story lengths are the same whichever theme is on.
BAND_HI=(2 15 30 55 85 110 135 160 185 215 245 275 355 455 575 725 755 785 815 845 880 915 945 1245 10000)
# per-band name and counter file (empty = no story) for each theme
SQUID_NAME=(golden dragon narwhal egg-hatch tortoise-hare seed-tree caterpillar ghost shark turtle-friend rabbit-friend twin crab bubbles octopus alligator humpty red-riding-hood bank-heist three-pigs pokemon-battle beanstalk cooking-meat food-snack plain)
SQUID_CTR=("" "" "" hatch race tree butterfly "" "" "" "" "" "" "" "" "" humpty redhood heist pigs pokebattle beanstalk cookmeat food "")
PLANE_NAME=(golden rocket unicorn-jet factory runway-race delay-board baggage-claim ghost-flight bird-strike bird-wingman airport-cat formation helicopter clouds prop-plane balloon humpty red-riding-hood flight three-pigs wright-brothers beanstalk apollo in-flight-meal plain)
PLANE_CTR=("" "" "" plane-factory plane-race plane-board plane-baggage "" "" "" "" "" "" "" "" "" plane-humpty plane-redhood plane-flight plane-pigs plane-wright plane-beanstalk plane-apollo plane-meal "")

# fairy tales told the same way in every theme ($1 band, $2 roll, $3 tick)
pick_tale() {
  case "$1" in
    16)
      # Humpty Dumpty
      case "$3" in
        1)       mascot="🥚🧱" ;;             # sitting on the wall
        2)       mascot="🥚💥🧱" ;;           # the great fall
        *)
          if [ $(($2 % 2)) -eq 0 ]; then
            mascot="🍳"        # couldn't be put together again
          else
            mascot="🥚✨"      # all the king's horses pulled it off
          fi
          ;;
      esac ;;
    17)
      # Little Red Riding Hood
      case "$3" in
        1)       mascot="🧒🔴🌲" ;;           # walking through the woods
        2)       mascot="🐺👀" ;;             # the wolf appears
        *)
          if [ $(($2 % 2)) -eq 0 ]; then
            mascot="🪓🐺"      # the woodsman saves the day
          else
            mascot="😈🐺"      # the wolf wins
          fi
          ;;
      esac ;;
    19)
      # the three little pigs
      case "$3" in
        1)       mascot="🐷🏠" ;;             # the straw house
        2)       mascot="🐺💨🏠" ;;           # the wolf huffs and puffs
        *)
          if [ $(($2 % 2)) -eq 0 ]; then
            mascot="🐺🍲" # the wolf ends up in the pot
          else
            mascot="🐷😱🐺" # the house comes down
          fi
          ;;
      esac ;;
    21)
      # Jack and the beanstalk
      case "$3" in
        1)       mascot="🫘🌱" ;;             # plants the bean
        2)       mascot="🌱🌿🌳" ;;           # it grows overnight
        3)       mascot="🧍🪜🌳" ;;           # Jack climbs up
        *)
          if [ $(($2 % 2)) -eq 0 ]; then
            mascot="🧍💰🪓🌳" # escapes with treasure, chops it down
          else
            mascot="🗿🌳" # the giant catches him
          fi
          ;;
      esac ;;
  esac
}

# squid theme (the default): sets mascot for band $1, roll $2, story tick $3
pick_squid() {
  local roll="$2" n="$3" food done_at dots
  case "$1" in
    0)  mascot="✨🦑✨" ;;    # golden squid, the rarest of all (0.02%)
    1)  mascot="🐉" ;;       # legendary: dragon squid (0.13%)
    2)  mascot="🦑🦄" ;;      # narwhal squid (0.15%)
    3)
      # the egg hatches after enough prompts in the same session
      if [ "$n" -ge 6 ]; then
        mascot="🦑🦑🦑"      # the egg hatched: squid triple
      else
        mascot="🦑🥚🦑"      # squid pair minding an egg (0.25%)
      fi ;;
    4)
      # tortoise and hare: hare sprints out, stalls, tortoise grinds it out
      case "$n" in
        1)       mascot="🐇╌╌╌╌╌🐢╌╌🏁" ;;  # hare bolts to an early lead
        2)       mascot="🐇╌╌╌╌🐢╌╌╌🏁" ;;
        3)       mascot="🐇╌╌╌🐢╌╌╌╌🏁" ;;
        4)       mascot="🐇╌╌🐢╌╌╌╌╌🏁" ;;
        5)       mascot="🐇╌🐢╌╌╌╌╌╌🏁" ;;
        6)       mascot="🐇🐢╌╌╌╌╌╌╌🏁" ;;  # tortoise finally catches up
        7)       mascot="🐢🐇╌╌╌╌╌╌╌🏁" ;;  # and passes
        *)       mascot="🏆🐢╌╌╌╌╌╌😴🐇" ;; # tortoise wins, hare's still napping (0.3%)
      esac ;;
    5)
      # a seed slowly grows into a fruit-bearing tree
      case "$n" in
        1)       mascot="🌱" ;;
        2)       mascot="🌿" ;;
        3)       mascot="🌳" ;;
        *)       mascot="🌳🍎" ;;            # bears fruit (0.25%)
      esac ;;
    6)
      # a caterpillar becomes a butterfly
      case "$n" in
        1)       mascot="🐛" ;;
        2)       mascot="🐛💤" ;;
        3)       mascot="🟤" ;;
        *)       mascot="🦋" ;;              # emerges (0.25%)
      esac ;;
    7)  mascot="👻🦑" ;;      # ghost squid (0.25%)
    8)  mascot="🦈🦑" ;;      # shark on the chase (0.25%)
    9)  mascot="🦑🐢" ;;      # squid + turtle friend (0.3%)
    10) mascot="🦑🐇" ;;      # squid + rabbit friend (0.3%)
    11) mascot="🦑🦑" ;;      # squid found its twin (0.3%)
    12) mascot="🦀" ;;       # crabby impostor (0.8%)
    13) mascot="🫧" ;;       # just bubbles, squid's hiding (1%)
    14) mascot="🐙" ;;       # octopus impostor (1.2%)
    15) mascot="🐊" ;;       # alligator swapped in (1.5%)
    18)
      # squid robs a bank
      case "$n" in
        1)       mascot="🦑🎭" ;;             # dons a mask
        2)       mascot="🦑💰🏦" ;;           # inside the vault
        *)
          if [ $((roll % 2)) -eq 0 ]; then
            mascot="🚔🦑" # caught red-handed
          else
            mascot="🦑💰🏝️" # gets away with it
          fi ;;
      esac ;;
    20)
      # pokemon battle, squid included
      case "$n" in
        1)       mascot="🦑⚡" ;;             # battle starts
        2)       mascot="🦑💥" ;;             # attacks clash
        *)
          if [ $((roll % 2)) -eq 0 ]; then
            mascot="🦑🏆" # squid wins
          else
            mascot="🦑😵" # squid faints
          fi ;;
      esac ;;
    22)
      # cooking meat
      case "$n" in
        1)       mascot="🥩" ;;               # raw
        2)       mascot="🥩🔥" ;;             # on the fire
        3)       mascot="🥩💨" ;;             # cooking through
        *)
          if [ $((roll % 2)) -eq 0 ]; then
            mascot="🍖✅" # cooked to perfection
          else
            mascot="🔥🍖⚫" # burnt to a crisp
          fi ;;
      esac ;;
    23)
      # common class: squid slowly eats a parcel of food, snack size varies the wait
      case $((roll % 4)) in
        0) food="🍎"; done_at=3 ;;   # apple: quick snack
        1) food="🍕"; done_at=5 ;;   # pizza: medium
        2) food="🍰"; done_at=5 ;;   # cake: medium
        *) food="🍗"; done_at=7 ;;   # turkey leg: slow feast
      esac
      if [ "$n" -gt "$done_at" ]; then
        mascot="🦑"                  # back to normal, fully digested
      elif [ "$n" -eq "$done_at" ]; then
        mascot="🦑😌"                # finished eating
      else
        dots=$(printf '.%.0s' $(seq 1 "$n"))
        mascot="🦑${food}${dots}"    # nibbling away
      fi ;;
    16|17|19|21) pick_tale "$1" "$roll" "$n" ;;
    *)  mascot="🦑" ;;
  esac
}

# plane theme (CLAUDE_STATUSLINE_THEME=plane): same bands, aviation eggs
pick_plane() {
  local roll="$2" n="$3" food done_at dots
  case "$1" in
    0)  mascot="✨✈️✨" ;;    # golden plane, the rarest of all (0.02%)
    1)  mascot="🚀" ;;       # legendary: a rocket (0.13%)
    2)  mascot="✈️🦄" ;;      # unicorn jet (0.15%)
    3)
      # a new plane rolls out of the factory after enough prompts
      if [ "$n" -ge 6 ]; then
        mascot="✈️✈️✈️"      # rolled out: a new plane joins the pair
      else
        mascot="✈️🏭✈️"      # two planes waiting by the factory (0.25%)
      fi ;;
    4)
      # runway race: the fast prop plane sprints out, stalls, the airliner grinds it out
      case "$n" in
        1)       mascot="🛩️╌╌╌╌╌✈️╌╌🏁" ;;  # prop plane bolts to an early lead
        2)       mascot="🛩️╌╌╌╌✈️╌╌╌🏁" ;;
        3)       mascot="🛩️╌╌╌✈️╌╌╌╌🏁" ;;
        4)       mascot="🛩️╌╌✈️╌╌╌╌╌🏁" ;;
        5)       mascot="🛩️╌✈️╌╌╌╌╌╌🏁" ;;
        6)       mascot="🛩️✈️╌╌╌╌╌╌╌🏁" ;;  # airliner finally catches up
        7)       mascot="✈️🛩️╌╌╌╌╌╌╌🏁" ;;  # and passes
        *)       mascot="🏆✈️╌╌╌╌╌╌😴🛩️" ;; # airliner wins, prop plane's pilot is napping (0.3%)
      esac ;;
    5)
      # the departures board: delayed, delayed again, finally boarding
      case "$n" in
        1)       mascot="✈️🕐" ;;
        2)       mascot="✈️🕑⏳" ;;
        3)       mascot="✈️🕒⏳⏳" ;;
        *)       mascot="🛫✅" ;;            # boarding at last (0.25%)
      esac ;;
    6)
      # baggage claim: the carousel goes round until your bag shows up
      case "$n" in
        1)       mascot="🛄" ;;
        2)       mascot="🛄💼" ;;
        3)       mascot="🛄💼🎒" ;;
        *)       mascot="🧳✅" ;;            # there it is (0.25%)
      esac ;;
    7)  mascot="👻✈️" ;;      # ghost flight (0.25%)
    8)  mascot="🐦✈️" ;;      # bird strike incoming (0.25%)
    9)  mascot="✈️🐦" ;;      # plane + bird wingman (0.3%)
    10) mascot="✈️🐈" ;;      # plane + airport cat (0.3%)
    11) mascot="✈️✈️" ;;      # flying in formation (0.3%)
    12) mascot="🚁" ;;       # helicopter impostor (0.8%)
    13) mascot="☁️" ;;       # just clouds, plane's lost in them (1%)
    14) mascot="🛩️" ;;       # prop plane impostor (1.2%)
    15) mascot="🎈" ;;       # a balloon drifted in (1.5%)
    18)
      # a flight: takeoff, cruise, then landed or diverted
      case "$n" in
        1)       mascot="🛫" ;;               # takeoff
        2)       mascot="✈️☁️" ;;             # cruising
        *)
          if [ $((roll % 2)) -eq 0 ]; then
            mascot="🛬✅" # landed on time
          else
            mascot="✈️🌩️" # storm ahead, diverted
          fi ;;
      esac ;;
    20)
      # the Wright Brothers at Kitty Hawk
      case "$n" in
        1)       mascot="🏖️🔧" ;;             # building the flyer on the dunes
        2)       mascot="🏖️🛩️💨" ;;           # off the rail
        *)
          if [ $((roll % 2)) -eq 0 ]; then
            mascot="🛩️🏆" # first powered flight
          else
            mascot="🛩️💥" # nose-dives into the sand, try again tomorrow
          fi ;;
      esac ;;
    22)
      # Apollo launch
      case "$n" in
        1)       mascot="🚀🔟" ;;             # countdown
        2)       mascot="🚀🔥" ;;             # ignition
        3)       mascot="🚀💨" ;;             # liftoff
        *)
          if [ $((roll % 2)) -eq 0 ]; then
            mascot="🚀🌕" # on to the moon
          else
            mascot="🚀⚠️🌍" # Houston, we have a problem: back home
          fi ;;
      esac ;;
    23)
      # common class: the in-flight meal, snack size varies the wait
      case $((roll % 4)) in
        0) food="🥜"; done_at=3 ;;   # peanuts: quick snack
        1) food="🥨"; done_at=5 ;;   # pretzels: medium
        2) food="🥪"; done_at=5 ;;   # sandwich: medium
        *) food="🍱"; done_at=7 ;;   # tray meal: slow feast
      esac
      if [ "$n" -gt "$done_at" ]; then
        mascot="✈️"                  # back to normal, tray table up
      elif [ "$n" -eq "$done_at" ]; then
        mascot="✈️😌"                # finished eating
      else
        dots=$(printf '.%.0s' $(seq 1 "$n"))
        mascot="✈️${food}${dots}"    # nibbling away
      fi ;;
    16|17|19|21) pick_tale "$1" "$roll" "$n" ;;
    *)  mascot="✈️" ;;
  esac
}

# index into BAND_HI for roll $1
band_of() {
  local i=0
  while [ "$1" -ge "${BAND_HI[$i]}" ]; do i=$((i + 1)); done
  echo "$i"
}

# --preview [squid|plane]: list every egg of a theme, one line each, then exit.
# Calls the same pick_* code the bar uses, but never touches a counter file.
preview() {
  local t i lo hi r n ctr name steps s seen
  for t in "$@"; do
    lo=0
    for i in "${!BAND_HI[@]}"; do
      hi=${BAND_HI[$i]}
      if [ "$t" = plane ]; then name=${PLANE_NAME[$i]}; ctr=${PLANE_CTR[$i]}
      else name=${SQUID_NAME[$i]}; ctr=${SQUID_CTR[$i]}; fi
      steps=(); seen="|"
      # rolls lo..lo+3 cover both roll%2 endings and all four roll%4 snacks
      for r in $(seq "$lo" $((lo + 3 < hi - 1 ? lo + 3 : hi - 1))); do
        for n in 1 2 3 4 5 6 7 8 9; do
          "pick_$t" "$i" "$r" "$n"
          case "$seen" in *"|$mascot|"*) ;; *) steps+=("$mascot"); seen+="$mascot|" ;; esac
          [ -z "$ctr" ] && break
        done
      done
      s=$(printf ' | %s' "${steps[@]}")
      printf '%s %s-%s %s %s: %s\n' "$t" "$lo" "$hi" "$name" "${ctr:--}" "${s:3}"
      lo=$hi
    done
  done
}

theme=$(printf '%s' "${CLAUDE_STATUSLINE_THEME:-}" | tr '[:upper:]' '[:lower:]')
[ "$theme" = plane ] || theme=squid

if [ "${1:-}" = "--preview" ]; then
  case "$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')" in
    "")    preview squid plane ;;
    squid) preview squid ;;
    plane) preview plane ;;
    *)     echo "usage: statusline.sh --preview [squid|plane]" >&2; exit 1 ;;
  esac
  exit 0
fi

input=$(cat)

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

# the mascot: one stable roll per session picks a band, story bands tick a counter
seed="${session_id:-$$-$cwd}"
roll=$(printf '%s' "$seed" | cksum | awk '{print $1 % 10000}')
band=$(band_of "$roll")
if [ "$theme" = plane ]; then ctr=${PLANE_CTR[$band]}; else ctr=${SQUID_CTR[$band]}; fi
n=0
[ -n "$ctr" ] && n=$(saga_tick "$ctr")
"pick_$theme" "$band" "$roll" "$n"

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
out="$(esc "$ORANGE;$FG") $mascot $short_cwd $(rst)"
prev_fg='38;2;214;93;14'

if [ -n "$branch" ]; then
  out+="$(esc "${prev_fg};${AQUA}")${SEP}$(rst)"
  out+="$(esc "$AQUA;$FG") $branch $(rst)"
  prev_fg='38;2;104;157;106'
fi

# model (color depends on model family)
read -r MODEL_BG model_next_fg MODEL_FG < <(model_color "$model")
model_label="$(strip_default_version "$model")"
if [ -n "$effort" ] && [ "$effort" != "null" ]; then
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
