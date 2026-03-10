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
NC='\033[0m'

SEP="${MUTED}  ${NC}"
MCP_CACHE_FILE="/tmp/claude_mcp_cache"
MCP_CACHE_TTL=120

# Single jq call — parse everything at once
IFS=$'\t' read -r MODEL DIR ADDED REMOVED CTX_PERCENT CTX_SIZE DURATION_MS API_DURATION_MS VIM_MODE < <(
  jq -r '[
    (.model.display_name // "Claude"),
    (.workspace.current_dir // "~"),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    ((.context_window.used_percentage // 0) | round),
    (.context_window.context_window_size // 0),
    (.cost.total_duration_ms // 0),
    (.cost.total_api_duration_ms // 0),
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

# Format token count (e.g. 150000 -> "150k", 1234 -> "1.2k")
format_tokens() {
  local n=$1
  if ((n >= 1000000)); then
    printf '%.1fM' "$(echo "$n / 1000000" | bc -l)"
  elif ((n >= 1000)); then
    printf '%.1fk' "$(echo "$n / 1000" | bc -l)"
  else
    printf '%s' "$n"
  fi
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

# Files modified in git
FILES_CHANGED=0
if git rev-parse --git-dir >/dev/null 2>&1; then
  FILES_CHANGED=$(git diff --name-only 2>/dev/null | wc -l)
  FILES_CHANGED=$((FILES_CHANGED + $(git diff --cached --name-only 2>/dev/null | wc -l)))
fi

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
HAS_GIT=false
if git rev-parse --git-dir >/dev/null 2>&1; then
  HAS_GIT=true
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

# Build line
DIR_NAME=$(basename "$DIR")
MCP_DISPLAY=$(format_mcp)

LINE="${BOLD}${HIGHLIGHT}${MODEL_ICON}  ${MODEL}${NC}"
LINE+="${SEP}${ACCENT}󰉋 ${DIR_NAME}${NC}"
if [ -n "$BRANCH" ]; then
  LINE+="${SEP}${SECONDARY}󰊢 ${BRANCH}${GIT_DIRTY}${NC}"
elif ! $HAS_GIT; then
  LINE+="${SEP}${MUTED}󰜛 no git${NC}"
fi
LINE+="${SEP}${SUCCESS}+${ADDED}${NC} ${ERROR}-${REMOVED}${NC}"
((FILES_CHANGED > 0)) && LINE+="${SEP}${ACCENT}󰈙 ${FILES_CHANGED}${NC}"
[ -n "$VIM_MODE" ] && LINE+="${SEP}${ACCENT}󰕷 ${VIM_MODE}${NC}"
LINE+="${SEP}${MCP_DISPLAY}"
TOKENS_DISPLAY=""
if ((CTX_SIZE > 0)); then
  USED_TOKENS=$((CTX_PERCENT * CTX_SIZE / 100))
  if ((CTX_PERCENT >= 80)); then
    TOKEN_COLOR="$HIGHLIGHT"
  elif ((CTX_PERCENT >= 50)); then
    TOKEN_COLOR="$_ORANGE"
  else
    TOKEN_COLOR="$SECONDARY"
  fi
  TOKENS_DISPLAY=" ${TOKEN_COLOR}$(format_tokens "$USED_TOKENS")/$(format_tokens "$CTX_SIZE")${NC}"
fi
LINE+="${SEP}${BAR_COLOR}context${NC} ${BAR} ${BAR_COLOR}${CTX_PERCENT}%${NC}${TOKENS_DISPLAY}"
LINE+="${SEP}${ACCENT}󰄉 ${DURATION}${NC} ${SECONDARY}󱨧 ${API_DURATION}${NC}"
LINE+="${SEP}${HIGHLIGHT}󰥔 ${CURRENT_TIME}${NC}"

echo -e "${LINE}\033[K"
