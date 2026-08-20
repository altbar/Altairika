#!/bin/bash
# ~/.claude/statusline.sh — Claude Code statusline (3 lines)
#
# Line 1: Opus 5 | К:  ◼◼◻◻◻◻◻◻◻◻ 26% (266k|1M) $0.21 | С: 266k $11.15
# Line 2: .      | 5ч: ◼◼◼◼◻◻◻◻◻◻ 40% 1:56 | Н: ● 88% 5ч13м
# Line 3: .      | Д: 6M $360 | 7д: 191M $4607 | 30д: 280M $6878

set -uo pipefail

INPUT=$(cat)
D="$HOME/.claude/cache/statusline"
NOW=$(date +%s)
mkdir -p "$D" 2>/dev/null

# ═══════════════════ PLATFORM SHIMS ═══════════════════
# macOS ships BSD stat/date; Linux and Git Bash on Windows ship the GNU ones, and
# the flags are not interchangeable. Probe the flavour once — do NOT chain them as
# `stat -f %m || stat -c %Y`: on GNU, `-f` means --file-system, so it prints
# filesystem info and exits 0, and the fallback never fires while the caller
# quietly gets garbage instead of an mtime.
if stat -c %Y . &>/dev/null; then
  _mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }   # GNU (Linux, Git Bash)
else
  _mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }   # BSD (macOS)
fi
# Here || is safe in the other direction: BSD's -v fails cleanly on GNU date
# (exit 1, nothing on stdout).
_days_ago() { date -v-"$1"d +"$2" 2>/dev/null || date -d "$1 days ago" +"$2" 2>/dev/null; }

# jq parses every value on all three lines. Without it the bar renders as `?` and
# zeros with no hint why — which reads like a broken script, not a missing package.
if ! command -v jq &>/dev/null; then
  printf 'jq не найден — статусбар не работает
'
  printf '.      | macOS: brew install jq · Linux: apt-get install -y jq
'
  printf '.      | Windows: winget install jqlang.jq (и перезапустить терминал)
'
  exit 0
fi

# ═══════════════════ LOCK HELPER ═══════════════════
# mkdir-based atomic lock — prevents N parallel statusline runs from
# spawning N copies of ccusage.
#
# The stale-lock threshold MUST exceed the slowest job it guards. It sat at 120s
# from when ccusage still finished in ~30s; as the transcripts grew the run passed
# 2 min, so every run outlived its own lock, the next redraw cleared it as "stale"
# and started a second copy. With ~50 sessions redrawing that stacked into a pile
# of 100%-CPU ccusage processes — load average ~20, WindowServer saturated, input
# lagging. ccusage 20 is back to ~10s, but keep the wide margin: the invariant is
# what matters, and the runtime grows again with the transcripts.
# Usage: _bg_locked <name> <cmd...>
_bg_locked() {
  local name=$1; shift
  local LOCK="$D/$name.lock"
  if [[ -d "$LOCK" ]]; then
    local age=$(( $(date +%s) - $(_mtime "$LOCK") ))
    (( age > 1800 )) && rmdir "$LOCK" 2>/dev/null
  fi
  (
    if mkdir "$LOCK" 2>/dev/null; then
      trap "rmdir '$LOCK' 2>/dev/null" EXIT INT TERM
      "$@"
    fi
  ) </dev/null &>/dev/null &
}

# ═══════════════════ CONFIG ═══════════════════
# The 5h/weekly limits come straight from the Claude Code statusline stdin payload:
#   .rate_limits.{five_hour,seven_day}.{used_percentage (0-100), resets_at (unix epoch)}
# No API, no token, no `user:profile` scope. An older version polled
# /api/oauth/usage with the short-lived claude.ai token; when that expired the line
# froze on a stale cache and showed `-`. Never route these two back through an API.

# ═══════════════════ HELPERS ═══════════════════

fmt() {
  local t=${1%%.*}
  t=${t#-}
  if (( t >= 1000000 )); then echo "$((t / 1000000))M"
  elif (( t >= 1000 ));    then echo "$((t / 1000))k"
  else echo "$t"; fi
}

bar() { # $1=pct $2=fill $3=empty $4=width
  local p=${1:-0} w=${4:-10} r=""
  (( p > 100 )) && p=100; (( p < 0 )) && p=0
  local n=$(( p * w / 100 ))
  for (( i=0; i<n; i++ )); do r+="$2"; done
  for (( i=n; i<w; i++ )); do r+="$3"; done
  printf '%s' "$r"
}

pie() { # pct → ○◔◑◕●
  local p=${1:-0}
  if   (( p <= 20 )); then printf '○'
  elif (( p <= 40 )); then printf '◔'
  elif (( p <= 60 )); then printf '◑'
  elif (( p <= 80 )); then printf '◕'
  else printf '●'; fi
}

dur() { # epoch → "6д22ч" (>1d) / "3ч15м" (<1d) / "-" (past or unknown)
  local t=${1:-0} now=${2:-0} d
  (( t > now )) || { printf '%s' '-'; return; }
  d=$(( t - now ))
  if (( d > 86400 )); then printf '%dд%dч' $(( d / 86400 )) $(( d % 86400 / 3600 ))
  else printf '%dч%02dм' $(( d / 3600 )) $(( d % 3600 / 60 )); fi
}

# ═══════════════════ PARSE STDIN JSON ═══════════════════

eval "$(echo "$INPUT" | jq -r '
  "MID=\(.model.id // "" | @sh)",
  "MDN=\(.model.display_name // "" | @sh)",
  "CW=\(.context_window.context_window_size // 200000)",
  "IT=\(.context_window.current_usage.input_tokens // 0)",
  "CR=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  "CC=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  "TI=\(.context_window.total_input_tokens // 0)",
  "TO=\(.context_window.total_output_tokens // 0)",
  "SC=\(.cost.total_cost_usd // 0)",
  "RFP=\((.rate_limits.five_hour.used_percentage // -1) | round)",
  "RFR=\(.rate_limits.five_hour.resets_at // 0)",
  "RSP=\((.rate_limits.seven_day.used_percentage // -1) | round)",
  "RSR=\(.rate_limits.seven_day.resets_at // 0)",
  "SI=\(.session_id // "x" | @sh)"
' 2>/dev/null)" 2>/dev/null || true

# ═══════════════════ LINE 1: MODEL + CONTEXT + SESSION ═══════════════════

case "${MID:-}" in
  *opus-4-8*)   M="Opus 4.8" ;;
  *opus-4-7*)   M="Opus 4.7" ;;
  *opus-4-6*)   M="Opus 4.6" ;;
  *opus-4-5*)   M="Opus 4.5" ;;
  *sonnet-4-6*) M="Sonnet 4.6" ;;
  *sonnet-4-5*) M="Sonnet 4.5" ;;
  *haiku-4-5*)  M="Haiku 4.5" ;;
  *)            M="${MDN:-${MID:-?}}" ;;
esac

# Context: input-side tokens vs effective window (minus 10k output buffer)
EFF=$(( ${CW:-200000} - 10000 )); (( EFF <= 0 )) && EFF=1
USED=$(( ${IT:-0} + ${CR:-0} + ${CC:-0} ))
PCT=$(( USED * 100 / EFF )); (( PCT > 100 )) && PCT=100

# Request cost — delta of session cost, persisted across redraws
CF="$D/${SI:-x}.cost"
PC=0; LR=0
if [[ -f "$CF" ]]; then
  read -r PC LR < "$CF" 2>/dev/null || { PC=0; LR=0; }
else
  # First invocation for this session — set baseline
  PC=${SC:-0}; LR=0
  printf '%s %s\n' "$PC" "$LR" > "$CF"
fi
# awk, not bc: bc ships with macOS but not with Git Bash on Windows, and is
# missing from minimal Linux images too. awk is everywhere, and does the same
# float subtract and compare — one dependency less to install.
DELTA=$(awk -v a="${SC:-0}" -v b="${PC:-0}" 'BEGIN{printf "%.10f", a-b}' 2>/dev/null || echo 0)
if awk -v d="${DELTA:-0}" 'BEGIN{exit !(d>0.001)}' 2>/dev/null; then
  LR=$DELTA
  printf '%s %s\n' "${SC:-0}" "$LR" > "$CF"
fi

ST=$(( ${TI:-0} + ${TO:-0} ))

printf '%s | К:  %s %d%% (%s|%s) $%.2f | С: %s $%.2f\n' \
  "$M" "$(bar $PCT '◼' '◻' 10)" "$PCT" \
  "$(fmt $USED)" "$(fmt ${CW:-200000})" \
  "${LR:-0}" "$(fmt $ST)" "${SC:-0}"

# Alignment padding for lines 2-3 (dot prevents leading-space trim)
PAD=".$(printf '%*s' ${#M} '')"

# ═══════════════════ LINE 2: RATE LIMITS (from CC stdin .rate_limits) ═══════════════════
# Claude Code passes live 5h/weekly limits in the statusline stdin payload
# (.rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}). No API call,
# no token, no `user:profile` scope — works natively on the yearly token.
# used_percentage is 0-100; resets_at is a unix epoch. (RFP/RFR/RSP/RSR parsed above.)

if (( ${RFP:--1} >= 0 )); then
  SP=${RFP}; (( SP < 0 )) && SP=0; (( SP > 100 )) && SP=100
  LP=${RSP:-0}; (( LP < 0 )) && LP=0; (( LP > 100 )) && LP=100

  # 5h reset → "H:MM"
  STIME=""
  if (( ${RFR:-0} > NOW )); then
    DIFF=$(( RFR - NOW ))
    STIME="$((DIFF / 3600)):$(printf '%02d' $((DIFF % 3600 / 60)))"
  fi

  printf '%s| 5ч: %s %d%% %s | Н: %s %d%% %s\n' \
    "$PAD" "$(bar $SP '◼' '◻' 10)" "$SP" "${STIME:--}" \
    "$(pie $LP)" "$LP" "$(dur "${RSR:-0}" "$NOW")"
else
  printf '%s| 5ч: — | Н: —\n' "$PAD"
fi

# ═══════════════════ LINE 3: EXPENSES (ccusage, 15min cache) ═══════════════════

EC="$D/expenses.json"

# Runs in the background QoS band (efficiency cores, yields to interactive work)
# so a ~2 min 100%-CPU scan never competes with the UI. nice is the fallback.
_fetch_exp() {
  command -v ccusage &>/dev/null || return 1
  local bg=(nice -n 19)
  command -v taskpolicy &>/dev/null && bg=(taskpolicy -b nice -n 19)
  # --offline: price from the bundled snapshot, no network at all. The remote
  # pricing file (raw.githubusercontent.com/BerriAI/litellm/...) is unreachable on
  # plenty of links — it hangs for ~90s and returns 0 bytes — and the fallback it
  # leaves behind prices every current model at $0.
  # Needs ccusage >= 20: the 18.x snapshot predates Opus 5 / Fable 5 / Sonnet 5,
  # so on that version --offline and LITELLM_PRICING_URL both still yielded $0.
  "${bg[@]}" ccusage daily --json --offline \
    --since "$(_days_ago 30 %Y%m%d)" \
    --until "$(date +%Y%m%d)" \
    --mode calculate 2>/dev/null
}

# Fully non-blocking: read cache, refresh in background if stale/missing.
# Lock prevents N statusline runs from forking N parallel ccusage processes
# (ccusage is heavy — ~100% CPU for ~30s on a 30-day window).
# Promote the temp file only when it holds real data: a ccusage run that is killed
# mid-write can still exit 0, and an exit-status-only check would move the empty
# file over a good cache — which the 15-min TTL then pins in place.
_refresh_expenses() {
  if _fetch_exp > "$EC.tmp" 2>/dev/null && jq -e '.daily | length > 0' "$EC.tmp" &>/dev/null; then
    mv "$EC.tmp" "$EC"
  else
    rm -f "$EC.tmp"
  fi
}
EDATA=""
if [[ -s "$EC" ]]; then
  EDATA=$(cat "$EC" 2>/dev/null)
  AGE=$(( NOW - $(_mtime "$EC") ))
  # 15 min, not 60s: the TTL must outlast the run (or the cache expires before it
  # is written and ccusage never stops), and with the daily figure gone from
  # line 3 the 7д/30д totals barely move anyway.
  (( AGE >= 900 )) && _bg_locked expenses _refresh_expenses
else
  _bg_locked expenses _refresh_expenses
fi

if [[ -n "${EDATA:-}" ]]; then
  TODAY=$(date +%Y-%m-%d)
  D7=$(_days_ago 7 %Y-%m-%d)

  # Aggregate: tokens = input + output + cacheCreation (no cacheRead), cost = totalCost.
  # The day key is `period` since ccusage 20 (`date` before it) — accept either,
  # or the 7-day window silently matches nothing and shows $0.
  eval "$(echo "$EDATA" | jq -r --arg today "$TODAY" --arg d7 "$D7" '
    .daily as $a |
    ($a | map(select((.period // .date // "") == $today)) |
      { t: ([.[] | .inputTokens + .outputTokens + .cacheCreationTokens] | add // 0),
        c: ([.[].totalCost] | add // 0) }) as $day |
    ($a | map(select((.period // .date // "") >= $d7)) |
      { t: ([.[] | .inputTokens + .outputTokens + .cacheCreationTokens] | add // 0),
        c: ([.[].totalCost] | add // 0) }) as $wk |
    ($a |
      { t: ([.[] | .inputTokens + .outputTokens + .cacheCreationTokens] | add // 0),
        c: ([.[].totalCost] | add // 0) }) as $mo |
    "DT=\($day.t)",
    "DC=\($day.c)",
    "WT=\($wk.t)",
    "WC=\($wk.c)",
    "MT=\($mo.t)",
    "MC=\($mo.c)"
  ' 2>/dev/null)" 2>/dev/null || true

  printf '%s| Д: %s $%.0f | 7д: %s $%.0f | 30д: %s $%.0f\n' \
    "$PAD" \
    "$(fmt ${DT:-0})" "${DC:-0}" \
    "$(fmt ${WT:-0})" "${WC:-0}" \
    "$(fmt ${MT:-0})" "${MC:-0}"
else
  printf '%s| Д: — | 7д: — | 30д: —\n' "$PAD"
fi
