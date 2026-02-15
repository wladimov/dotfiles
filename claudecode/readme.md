# Statusline

Custom multiline statusline for Claude Code. Bash script that receives JSON via stdin and renders two status lines using the Tokyo Night palette, Nerd Fonts icons, and semantic colors.

## Layout

Two lines. The first shows project info, the second shows session metrics.

```
  Opus 4.6  󰉋 mi-app  󰊢 main*  +261 -37  󰈙 3  server1 server2  󰏗 2.1.42  󰖟 bf63e846
context ████████░░ 42%  󰄉 5m 32s 󱨧 1m 12s  󰍛 68% 󰘚 4%  󰥔 13:32
```

### Line 1 — Project

| Section     | Icon                             | Color     | Description                                                 |
| ----------- | -------------------------------- | --------- | ----------------------------------------------------------- |
| Model       | Opus, 󰈙 Sonnet, 󰲓 Haiku, 󰚩 other | magenta   | Active model (bold)                                         |
| Directory   | 󰉋                                | yellow    | Current directory (basename)                                |
| Git         | 󰊢                                | cyan      | Branch + dirty flag (`*`) if there are changes              |
| Claude diff | +N -N                            | green/red | Lines added/removed by Claude via Edit/Write in the session |
| Git files   | 󰈙                                | yellow    | Modified files in git (only if > 0)                         |
| Vim mode    | 󰕷                                | yellow    | NORMAL/INSERT (only if vim mode is active)                  |
| MCP         | —                                | green     | Connected MCP servers or "no mcp" (gray)                    |
| Version     | 󰏗                                | cyan      | Claude Code version                                         |
| Session ID  | 󰖟                                | blue      | First 8 chars of the session UUID                           |

### Line 2 — Metrics

| Section          | Icon | Color   | Description                                                                                                                             |
| ---------------- | ---- | ------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Context          | █░   | dynamic | 10-block bar: `█` filled, `░` empty. Color by usage: green <50%, yellow 50-79%, red >=80%. Label `context` and `%` share the same color |
| Session duration | 󰄉    | yellow  | Total time since the session started                                                                                                    |
| API duration     | 󱨧    | cyan    | Cumulative time waiting for API responses                                                                                               |
| RAM              | 󰍛    | green   | System RAM usage %                                                                                                                      |
| CPU              | 󰘚    | yellow  | Load average normalized by cores                                                                                                        |
| Time             | 󰥔    | magenta | Current time HH:MM                                                                                                                      |

## Claude Code JSON

The script receives via stdin a JSON object with session telemetry. Fields used:

```json
{
  "model": { "display_name": "Opus 4.6" },
  "workspace": { "current_dir": "/path/to/project" },
  "cost": {
    "total_lines_added": 156,
    "total_lines_removed": 23,
    "total_duration_ms": 45000,
    "total_api_duration_ms": 2300
  },
  "context_window": {
    "used_percentage": 42
  },
  "session_id": "bf63e846-ca46-4c0c-b6a2-3ba03968fc3f",
  "version": "2.1.42",
  "vim": { "mode": "NORMAL" }
}
```

`vim.mode` only appears if vim mode is enabled. `used_percentage` can be `null` before the first API call.

## Requirements

- Linux / WSL2
- `jq` installed (`brew install jq`)
- Nerd Fonts in the terminal

## Installation

```bash
# Copy the script
cp claudecode/statusline.sh ~/.claude/statusline.sh

# Ensure execute permissions
chmod +x ~/.claude/statusline.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
```

Restart Claude Code to apply changes.

## Color customization

The script separates **palette** from **semantic roles**. To change the theme, only modify the `_` variables at the top of the script:

```bash
# Tokyo Night palette
_BLUE='\033[38;5;111m'        # #7aa2f7
_CYAN='\033[38;5;117m'        # #7dcfff
_YELLOW='\033[38;5;179m'      # #e0af68
_GREEN='\033[38;5;150m'       # #9ece6a
_RED='\033[38;5;204m'         # #f7768e
_MAGENTA='\033[38;5;141m'     # #bb9af7
_ORANGE='\033[38;5;209m'      # #ff9e64
_MUTED='\033[38;5;60m'        # #565f89
```

Semantic roles (`PRIMARY`, `ACCENT`, `SUCCESS`, etc.) point to the palette. The rest of the script remains untouched.

### Color map

| Role      | Color   | Hex     | Usage                                                 |
| --------- | ------- | ------- | ----------------------------------------------------- |
| PRIMARY   | blue    | #7aa2f7 | Session ID                                            |
| SECONDARY | cyan    | #7dcfff | Git branch, version, API duration                     |
| ACCENT    | yellow  | #e0af68 | Directory, git files, vim mode, session duration, CPU |
| SUCCESS   | green   | #9ece6a | Lines added, MCP servers, RAM                         |
| ERROR     | red     | #f7768e | Lines removed, context bar >=80%                      |
| HIGHLIGHT | magenta | #bb9af7 | Model, time                                           |
| MUTED     | gray    | #565f89 | Separators, empty bar `░`, "no mcp"                   |
