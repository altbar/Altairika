#!/bin/bash
# ~/.claude/statusline.sh — Claude Code statusline (3 lines)
#
# Line 1: Opus 4.6 | К: ◆◆◆◆◆◆◆◇◇◇ 76% (128k|200k) $0.28 | С: 162k $6.05
# Line 2: .        | 5ч: ◼◼◼◼◼◼◼◻◻◻ 71% 0:14 | Н: ◑ 61% ср 18.02
# Line 3: .        | Д: 2M $35 | 7д: 21M $464 | 30д: 115M $1228

set -uo pipefail

INPUT=$(cat)
D="$HOME/.claude/cache/statusline"
mkdir -p "$D" 2>/dev/null

# ═══════════════════ CONFIG ═══════════════════
# API: https://api.anthropic.com/api/oauth/usage
# Response: { "five_hour": { "utilization": 12.0, "resets_at": "..." }, "seven_day": { ... } }
# utilization is already a percentage (0-100)

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
  "SI=\(.session_id // "x" | @sh)"
' 2>/dev/null)" 2>/dev/null || true

# ═══════════════════ LINE 1: MODEL + CONTEXT + SESSION ═══════════════════

case "${MID:-}" in
  *opus-4-6*)   M="Opus 4.6" ;;
  *opus-4-5*)   M="Opus 4.5" ;;
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

# ═══════════════════ LINE 2: LIMITS (OAuth API, 15min cache) ═══════════════════

LC="$D/limits.json"

_fetch_lim() {
  local tk
  tk=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
    | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null) || return 1
  [[ -z "$tk" ]] && return 1
  local r=""
  r=$(curl -sf --connect-timeout 3 --max-time 5 \
    -H "Authorization: Bearer $tk" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Accept: application/json" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || return 1
  [[ -z "$r" || "${r:-}" == "<"* ]] && return 1
  echo "$r" | jq empty 2>/dev/null || return 1
  echo "$r"; return 0
}

# Fully non-blocking: read cache, refresh in background if stale/missing
LDATA=""
if [[ -f "$LC" ]]; then
  LDATA=$(cat "$LC" 2>/dev/null)
  AGE=$(( $(date +%s) - $(stat -f %m "$LC" 2>/dev/null || echo 0) ))
  (( AGE >= 900 )) && \
    ( _fetch_lim > "$LC.tmp" 2>/dev/null && mv "$LC.tmp" "$LC" && rm -f "$LC.neg" \
      || { rm -f "$LC.tmp"; touch "$LC.neg"; } ) </dev/null &>/dev/null &
elif [[ ! -f "$LC.neg" ]] || \
     (( $(date +%s) - $(stat -f %m "$LC.neg" 2>/dev/null || echo 0) >= 300 )); then
  # No cache + no recent failure → background fetch (negative cache 5min)
  ( _fetch_lim > "$LC.tmp" 2>/dev/null && mv "$LC.tmp" "$LC" && rm -f "$LC.neg" \
    || { rm -f "$LC.tmp"; touch "$LC.neg"; } ) </dev/null &>/dev/null &
fi

# Save raw response for debugging
[[ -n "${LDATA:-}" ]] && echo "$LDATA" > "$D/limits_debug.json" 2>/dev/null

if [[ -n "${LDATA:-}" ]]; then
  # Parse utilization (already a percentage) and resets_at from API
  SP=$(echo "$LDATA" | jq -r '.five_hour.utilization // 0' 2>/dev/null) || SP=0
  SR=$(echo "$LDATA" | jq -r '.five_hour.resets_at // ""' 2>/dev/null) || SR=""
  LP=$(echo "$LDATA" | jq -r '.seven_day.utilization // 0' 2>/dev/null) || LP=0
  LRE=$(echo "$LDATA" | jq -r '.seven_day.resets_at // ""' 2>/dev/null) || LRE=""

  # Fix null/empty
  [[ "$SP" == "null" || -z "$SP" ]] && SP=0
  [[ "$LP" == "null" || -z "$LP" ]] && LP=0
  [[ "$SR" == "null" ]] && SR=""
  [[ "$LRE" == "null" ]] && LRE=""

  # Truncate to integer for bar/pie
  SP=${SP%%.*}; (( SP > 100 )) && SP=100
  LP=${LP%%.*}; (( LP > 100 )) && LP=100

  # Time until 5h reset (parse ISO 8601 UTC → epoch)
  STIME=""
  if [[ -n "$SR" ]]; then
    # Convert UTC time: strip fractional seconds and tz, append UTC
    CLEAN="${SR%%[.+]*}"
    RST=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$CLEAN" "+%s" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    DIFF=$(( RST - NOW ))
    (( DIFF > 0 )) && STIME="$((DIFF / 3600)):$(printf '%02d' $((DIFF % 3600 / 60)))"
  fi

  # Weekly time until reset (e.g. "6д22ч" or "3ч15м")
  LTIME=""
  if [[ -n "$LRE" ]]; then
    CLEAN="${LRE%%[.+]*}"
    LRST=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$CLEAN" "+%s" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    LDIFF=$(( LRST - NOW ))
    if (( LDIFF > 86400 )); then
      LTIME="$((LDIFF / 86400))д$((LDIFF % 86400 / 3600))ч"
    elif (( LDIFF > 0 )); then
      LTIME="$((LDIFF / 3600))ч$(printf '%02d' $((LDIFF % 3600 / 60)))м"
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

# Fully non-blocking: read cache, refresh in background if stale/missing
EDATA=""
if [[ -f "$EC" ]]; then
  EDATA=$(cat "$EC" 2>/dev/null)
  AGE=$(( $(date +%s) - $(stat -f %m "$EC" 2>/dev/null || echo 0) ))
  (( AGE >= 60 )) && \
    ( _fetch_exp > "$EC.tmp" 2>/dev/null && mv "$EC.tmp" "$EC" || rm -f "$EC.tmp" ) </dev/null &>/dev/null &
else
  ( _fetch_exp > "$EC.tmp" 2>/dev/null && mv "$EC.tmp" "$EC" || rm -f "$EC.tmp" ) </dev/null &>/dev/null &
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
