#!/bin/bash
set -euo pipefail

# Tokyo Night palette
_BLUE='\033[38;5;111m'    # #7aa2f7
_CYAN='\033[38;5;117m'    # #7dcfff
_YELLOW='\033[38;5;179m'  # #e0af68
_GREEN='\033[38;5;150m'   # #9ece6a
_RED='\033[38;5;204m'     # #f7768e
_MAGENTA='\033[38;5;141m' # #bb9af7
_ORANGE='\033[38;5;209m'  # #ff9e64
_MUTED='\033[38;5;60m'    # #565f89

# Semantic roles — change palette above, not these
PRIMARY="$_BLUE"
ACCENT="$_YELLOW"
SECONDARY="$_CYAN"
SUCCESS="$_GREEN"
ERROR="$_RED"
HIGHLIGHT="$_MAGENTA"
MUTED="$_MUTED"
BOLD='\033[1m'
STRIKE='\033[9m'
NC='\033[0m'

SEP="${MUTED}  ${NC}"
MCP_CACHE_FILE="/tmp/claude_mcp_cache"
MCP_CACHE_TTL=120

# Single jq call — parse everything at once
IFS=$'\t' read -r MODEL DIR ADDED REMOVED CTX_PERCENT DURATION_MS API_DURATION_MS SESSION_ID VERSION VIM_MODE < <(
  jq -r '[
    (.model.display_name // "Claude"),
    (.workspace.current_dir // "~"),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.context_window.used_percentage // 0),
    (.cost.total_duration_ms // 0),
    (.cost.total_api_duration_ms // 0),
    (.session_id // ""),
    (.version // ""),
    (.vim.mode // "")
  ] | @tsv'
)

# MCP servers (cached, Linux stat)
get_mcp_servers() {
  if [ -f "$MCP_CACHE_FILE" ]; then
    local CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$MCP_CACHE_FILE" 2>/dev/null || echo 0)))
    if [ "$CACHE_AGE" -lt "$MCP_CACHE_TTL" ]; then
      <"$MCP_CACHE_FILE" read -r CACHED
      echo "$CACHED"
      return
    fi
  fi

  local SERVERS=""
  if [ -n "$DIR" ]; then
    SERVERS=$(jq -r ".projects[\"$DIR\"].mcpServers // {} | keys[]" "$HOME/.claude.json" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  fi
  if [ -z "$SERVERS" ]; then
    SERVERS=$(jq -r ".projects[\"$HOME\"].mcpServers // {} | keys[]" "$HOME/.claude.json" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  fi

  echo "$SERVERS" >"$MCP_CACHE_FILE"
  echo "$SERVERS"
}

format_mcp() {
  local servers
  servers=$(get_mcp_servers)
  if [ -z "$servers" ]; then
    echo "${MUTED}no mcp${NC}"
    return
  fi
  local result=""
  IFS=',' read -ra LIST <<<"$servers"
  for srv in "${LIST[@]}"; do
    [ -n "$result" ] && result+=" "
    result+="${SUCCESS}${srv}${NC}"
  done
  echo "$result"
}

# Format duration (ms -> Xm Ys)
format_duration() {
  local ms=$1
  local secs=$((ms / 1000))
  local mins=$((secs / 60))
  secs=$((secs % 60))
  if ((mins > 0)); then
    printf '%sm %ss' "$mins" "$secs"
  else
    printf '%ss' "$secs"
  fi
}

DURATION=$(format_duration "$DURATION_MS")
API_DURATION=$(format_duration "$API_DURATION_MS")

# Session ID (first 8 chars)
SHORT_SESSION="${SESSION_ID:0:8}"

# Files modified in git
FILES_CHANGED=0
if git rev-parse --git-dir >/dev/null 2>&1; then
  FILES_CHANGED=$(git diff --name-only 2>/dev/null | wc -l)
  FILES_CHANGED=$((FILES_CHANGED + $(git diff --cached --name-only 2>/dev/null | wc -l)))
fi

# System resources (Linux/WSL2)
RAM_USED=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.0f", (t-a)/t*100}' /proc/meminfo 2>/dev/null || echo "0")
CPU_LOAD=$(awk '{printf "%.0f", $1 * 100 / '"$(nproc 2>/dev/null || echo 1)"'}' /proc/loadavg 2>/dev/null || echo "0")

# Time
CURRENT_TIME=$(date +%H:%M)

# Model icon (Nerd Fonts)
MODEL_ICON="󰚩"
case "$MODEL" in
*Opus*) MODEL_ICON=" " ;;
*Sonnet*) MODEL_ICON="󰈙" ;;
*Haiku*) MODEL_ICON="󰲓 " ;;
esac

# Git info
BRANCH=""
GIT_DIRTY=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  [[ -n $(git status --porcelain 2>/dev/null) ]] && GIT_DIRTY="*"
fi

# Progress bar (10 blocks, color by usage)
BAR_WIDTH=10
FILLED=$((CTX_PERCENT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))

if ((CTX_PERCENT >= 80)); then
  BAR_COLOR="$ERROR"
elif ((CTX_PERCENT >= 50)); then
  BAR_COLOR="$ACCENT"
else
  BAR_COLOR="$SUCCESS"
fi

BAR="${BAR_COLOR}"
for ((i = 0; i < FILLED; i++)); do BAR+="█"; done
BAR+="${MUTED}"
for ((i = 0; i < EMPTY; i++)); do BAR+="░"; done
BAR+="${NC}"

# Build lines
DIR_NAME=$(basename "$DIR")
MCP_DISPLAY=$(format_mcp)

# Line 1: Project info
L1="${BOLD}${HIGHLIGHT}${MODEL_ICON}  ${MODEL}${NC}"
L1+="${SEP}${ACCENT}󰉋 ${DIR_NAME}${NC}"
[ -n "$BRANCH" ] && L1+="${SEP}${SECONDARY}󰊢 ${BRANCH}${GIT_DIRTY}${NC}"
L1+="${SEP}${SUCCESS}+${ADDED}${NC} ${ERROR}-${REMOVED}${NC}"
((FILES_CHANGED > 0)) && L1+="${SEP}${ACCENT}󰈙 ${FILES_CHANGED}${NC}"
[ -n "$VIM_MODE" ] && L1+="${SEP}${ACCENT}󰕷 ${VIM_MODE}${NC}"
L1+="${SEP}${MCP_DISPLAY}"
L1+="${SEP}${SECONDARY}󰏗 ${VERSION}${NC}"
L1+="${SEP}${PRIMARY}󰖟 ${SHORT_SESSION}${NC}"

# Line 2: Context, tokens, system, time
L2="${BAR_COLOR}context${NC} ${BAR} ${BAR_COLOR}${CTX_PERCENT}%${NC}"
L2+="${SEP}${ACCENT}󰄉 ${DURATION}${NC} ${SECONDARY}󱨧 ${API_DURATION}${NC}"
L2+="${SEP}${SUCCESS}󰍛 ${RAM_USED}%${NC} ${ACCENT}󰘚 ${CPU_LOAD}%${NC}"
L2+="${SEP}${HIGHLIGHT}󰥔 ${CURRENT_TIME}${NC}"

echo -e "${L1}\033[K"
echo -e "${L2}\033[K"
