#!/bin/bash
# Claude Code status line
# Line 1: Model | Effort | Git branch
# Line 2: Context bar | Cost | Session duration

input=$(cat)

# --- Extract fields ---
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
MODEL_ID=$(echo "$input" | jq -r '.model.id // ""')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

# --- Colors ---
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Effort / thinking indicator ---
# Infer from model ID: [1m] = extended context, likely high effort
EFFORT=""
if echo "$MODEL_ID" | grep -q '\[1m\]'; then
    EFFORT="${CYAN}1M${RESET}"
else
    CTX_K=$((CTX_SIZE / 1000))
    EFFORT="${DIM}${CTX_K}K${RESET}"
fi

# --- Git branch ---
BRANCH=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
fi

# --- Context bar (color-coded) ---
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

BAR_WIDTH=15
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /█}"
[ "$EMPTY" -gt 0 ] && printf -v PAD "%${EMPTY}s" && BAR="${BAR}${PAD// /░}"

# --- Duration ---
MINS=$((DURATION_MS / 60000))
SECS=$(((DURATION_MS % 60000) / 1000))

# --- Cost ---
COST_FMT=$(printf '$%.2f' "$COST")

# --- Line 1: Model | Effort | Git ---
LINE1="${BOLD}${MODEL}${RESET} ${DIM}|${RESET} ${EFFORT}"
[ -n "$BRANCH" ] && LINE1="${LINE1} ${DIM}|${RESET} ${GREEN}${BRANCH}${RESET}"

# --- Line 2: Context bar | Cost | Duration ---
LINE2="${BAR_COLOR}${BAR}${RESET} ${PCT}% ${DIM}|${RESET} ${YELLOW}${COST_FMT}${RESET} ${DIM}|${RESET} ${DIM}${MINS}m ${SECS}s${RESET}"

echo -e "$LINE1"
echo -e "$LINE2"
