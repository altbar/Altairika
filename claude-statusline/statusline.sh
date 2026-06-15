#!/bin/bash
# ~/.claude/statusline.sh — Claude Code statusline (3 lines)
#
# Line 1: Opus 4.8 | К: ◆◆◇◇◇◇◇◇◇◇ 21% (214k|1M) $0.28 | С: 215k $6.05
# Line 2: .        | 5ч: ◼◻◻◻◻◻◻◻◻◻ 18% 3:02 | Н: ◔ 34% 2д12ч
# Line 3: .        | Д: 5M $99 | 7д: 62M $684 | 30д: 156M $2419

set -uo pipefail

INPUT=$(cat)
D="$HOME/.claude/cache/statusline"
mkdir -p "$D" 2>/dev/null

# ═══════════════════ LOCK HELPER ═══════════════════
# mkdir-based atomic lock — prevents N parallel statusline runs from
# spawning N copies of ccusage. Stale locks (>120s) are auto-cleared.
# Usage: _bg_locked <name> <cmd...>
_bg_locked() {
  local name=$1; shift
  local LOCK="$D/$name.lock"
  if [[ -d "$LOCK" ]]; then
    local age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    (( age > 120 )) && rmdir "$LOCK" 2>/dev/null
  fi
  (
    if mkdir "$LOCK" 2>/dev/null; then
      trap "rmdir '$LOCK' 2>/dev/null" EXIT INT TERM
      "$@"
    fi
  ) </dev/null &>/dev/null &
}

# ═══════════════════ CONFIG ═══════════════════
# Rate limits come straight from the Claude Code statusline stdin payload:
#   .rate_limits.{five_hour,seven_day}.{used_percentage (0-100), resets_at (unix epoch)}
# No API/token needed. (Previously fetched /api/oauth/usage, which needs the
# user:profile scope the yearly token lacks — see memory: statusline-limits-token.)

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
  "RFP=\(.rate_limits.five_hour.used_percentage // -1)",
  "RFR=\(.rate_limits.five_hour.resets_at // 0)",
  "RSP=\(.rate_limits.seven_day.used_percentage // -1)",
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
DELTA=$(echo "${SC:-0} - ${PC:-0}" | bc -l 2>/dev/null || echo 0)
if (( $(echo "${DELTA:-0} > 0.001" | bc -l 2>/dev/null || echo 0) )); then
  LR=$DELTA
  printf '%s %s\n' "${SC:-0}" "$LR" > "$CF"
fi

ST=$(( ${TI:-0} + ${TO:-0} ))

printf '%s | К: %s %d%% (%s|%s) $%.2f | С: %s $%.2f\n' \
  "$M" "$(bar $PCT '◆' '◇' 10)" "$PCT" \
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
  NOW=$(date +%s)
  SP=${RFP}; (( SP < 0 )) && SP=0; (( SP > 100 )) && SP=100
  LP=${RSP:-0}; (( LP < 0 )) && LP=0; (( LP > 100 )) && LP=100

  # 5h reset → "H:MM"
  STIME=""
  if (( ${RFR:-0} > NOW )); then
    DIFF=$(( RFR - NOW ))
    STIME="$((DIFF / 3600)):$(printf '%02d' $((DIFF % 3600 / 60)))"
  fi

  # Weekly reset → "6д22ч" (>1d) or "3ч15м" (<1d)
  LTIME=""
  if (( ${RSR:-0} > NOW )); then
    LD=$(( RSR - NOW ))
    if (( LD > 86400 )); then
      LTIME="$((LD / 86400))д$((LD % 86400 / 3600))ч"
    else
      LTIME="$((LD / 3600))ч$(printf '%02d' $((LD % 3600 / 60)))м"
    fi
  fi

  printf '%s| 5ч: %s %d%% %s | Н: %s %d%% %s\n' \
    "$PAD" "$(bar $SP '◼' '◻' 10)" "$SP" "${STIME:--}" \
    "$(pie $LP)" "$LP" "${LTIME:--}"
else
  printf '%s| 5ч: — | Н: —\n' "$PAD"
fi

# ═══════════════════ LINE 3: EXPENSES (ccusage, 60s cache) ═══════════════════

EC="$D/expenses.json"

_fetch_exp() {
  command -v ccusage &>/dev/null || return 1
  ccusage daily --json \
    --since "$(date -v-30d +%Y%m%d)" \
    --until "$(date +%Y%m%d)" \
    --mode calculate 2>/dev/null
}

# Fully non-blocking: read cache, refresh in background if stale/missing.
# Lock prevents N statusline runs from forking N parallel ccusage processes
# (ccusage is heavy — ~100% CPU for ~30s on a 30-day window).
_refresh_expenses() {
  _fetch_exp > "$EC.tmp" 2>/dev/null && mv "$EC.tmp" "$EC" || rm -f "$EC.tmp"
}
EDATA=""
if [[ -f "$EC" ]]; then
  EDATA=$(cat "$EC" 2>/dev/null)
  AGE=$(( $(date +%s) - $(stat -f %m "$EC" 2>/dev/null || echo 0) ))
  (( AGE >= 60 )) && _bg_locked expenses _refresh_expenses
else
  _bg_locked expenses _refresh_expenses
fi

if [[ -n "${EDATA:-}" ]]; then
  TODAY=$(date +%Y-%m-%d)
  D7=$(date -v-7d +%Y-%m-%d)

  # Aggregate: tokens = input + output + cacheCreation (no cacheRead), cost = totalCost
  eval "$(echo "$EDATA" | jq -r --arg today "$TODAY" --arg d7 "$D7" '
    .daily as $a |
    ($a | map(select(.date == $today)) |
      { t: ([.[] | .inputTokens + .outputTokens + .cacheCreationTokens] | add // 0),
        c: ([.[].totalCost] | add // 0) }) as $day |
    ($a | map(select(.date >= $d7)) |
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
