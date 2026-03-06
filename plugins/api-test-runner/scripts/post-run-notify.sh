#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# post-run-notify.sh
# PostToolUse (Bash) hook: detects when api-runner.js was just executed and
# prints the dashboard HTML link in a prominent banner.
#
# Detection strategy (all three must agree before printing):
#   1. Tool input (stdin JSON or env vars) contains "api-runner"
#   2. results/history.json was modified within the last FRESHNESS_SECS seconds
#   3. The result entry in history shows passed=true or passed=false (valid run)
# ─────────────────────────────────────────────────────────────────────────────

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
HISTORY_FILE="${PLUGIN_ROOT}/results/history.json"
MARKER_FILE="${PLUGIN_ROOT}/results/.last-run"
PORT="${DASHBOARD_PORT:-3737}"
FRESHNESS_SECS=15   # seconds since history.json write = "just ran"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — read tool input from stdin (Claude Code pipes JSON to command hooks)
# ─────────────────────────────────────────────────────────────────────────────
TOOL_INPUT=""

# Read stdin non-blocking (timeout 0.2s so we never block)
if command -v timeout &>/dev/null; then
  TOOL_INPUT=$(timeout 0.2s cat 2>/dev/null) || true
else
  # Fallback: read with bash built-in timeout
  read -t 0.2 -d '' TOOL_INPUT 2>/dev/null || true
fi

# Also accept from environment variables that Claude Code may set
TOOL_INPUT="${TOOL_INPUT:-${CLAUDE_TOOL_INPUT:-${TOOL_INPUT_COMMAND:-${ARGUMENTS:-}}}}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — check if this Bash call involved api-runner.js
# ─────────────────────────────────────────────────────────────────────────────
is_api_runner_call() {
  # Direct match in tool input JSON
  if echo "$TOOL_INPUT" | grep -qi "api-runner"; then
    return 0
  fi
  # Match common aliases / npm scripts that wrap api-runner
  if echo "$TOOL_INPUT" | grep -qiE "npm run (test|report)|node.*scripts/"; then
    return 0
  fi
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — check if history.json was updated very recently
# ─────────────────────────────────────────────────────────────────────────────
history_just_updated() {
  [ -f "$HISTORY_FILE" ] || return 1

  local modified now diff
  # GNU stat (Linux / Git Bash on Windows)
  modified=$(stat -c '%Y' "$HISTORY_FILE" 2>/dev/null) || \
  # BSD stat (macOS)
  modified=$(stat -f '%m'  "$HISTORY_FILE" 2>/dev/null) || \
  modified=0

  now=$(date +%s 2>/dev/null || echo 0)
  diff=$(( now - modified ))
  [ "$diff" -le "$FRESHNESS_SECS" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — read last result from history for the status line
# ─────────────────────────────────────────────────────────────────────────────
get_last_result_summary() {
  command -v node &>/dev/null || { echo "unknown"; return; }
  node -e "
    try {
      const h = require('${HISTORY_FILE}');
      const r = h[0];
      if (!r) { process.stdout.write('unknown'); process.exit(); }
      const icon   = r.passed ? '✅' : '❌';
      const status = r.status || '?';
      const dur    = r.duration ? r.duration + 'ms' : '?';
      const ep     = (r.method || '') + ' ' + (r.endpoint || '');
      process.stdout.write(icon + ' ' + status + '  ' + ep.trim() + '  (' + dur + ')');
    } catch(e) { process.stdout.write('unknown'); }
  " 2>/dev/null || echo "unknown"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — check if dashboard server is reachable
# ─────────────────────────────────────────────────────────────────────────────
dashboard_running() {
  if command -v curl &>/dev/null; then
    curl -s --max-time 1 "http://localhost:${PORT}/api/stats" > /dev/null 2>&1
  elif command -v wget &>/dev/null; then
    wget -q --timeout=1 -O /dev/null "http://localhost:${PORT}/api/stats" 2>/dev/null
  else
    # Fallback: check if port is open using bash TCP
    (exec 3<>/dev/tcp/localhost/${PORT}) 2>/dev/null && exec 3>&-
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main — only print the banner when an api-runner run was just detected
# ─────────────────────────────────────────────────────────────────────────────
should_notify=0

# Primary signal: .last-run marker written by api-runner.js --report
# (most reliable — written only by api-runner, not by any other Bash command)
marker_just_written() {
  [ -f "$MARKER_FILE" ] || return 1
  local modified now diff
  modified=$(stat -c '%Y' "$MARKER_FILE" 2>/dev/null || stat -f '%m' "$MARKER_FILE" 2>/dev/null || echo 0)
  now=$(date +%s 2>/dev/null || echo 0)
  diff=$(( now - modified ))
  [ "$diff" -le "$FRESHNESS_SECS" ]
}

if marker_just_written; then
  should_notify=1
elif is_api_runner_call && history_just_updated; then
  should_notify=1
fi

[ "$should_notify" -eq 0 ] && exit 0

# ─────────────────────────────────────────────────────────────────────────────
# Print the dashboard banner
# ─────────────────────────────────────────────────────────────────────────────

LAST=$(get_last_result_summary)

# Choose dashboard start hint based on whether server is already up
if dashboard_running; then
  SERVER_LINE="  Server running  ·  open the link above in your browser"
else
  SERVER_LINE="  Start server →  node ${PLUGIN_ROOT}/scripts/dashboard-server.js"
fi

# Column width for the box
BOX_W=60

pad() {
  # pad string $1 to width $BOX_W with trailing spaces, then add right border
  local s="$1"
  local len=${#s}
  local pad=$(( BOX_W - len ))
  printf '%s%*s' "$s" "$pad" ""
}

printf '\n'
printf '\033[0;36m┌%s┐\033[0m\n' "$(printf '─%.0s' $(seq 1 $BOX_W))"
printf '\033[0;36m│\033[0m \033[1m%-*s\033[0m \033[0;36m│\033[0m\n' $(( BOX_W - 2 )) "📊  API Test Runner — Results Dashboard"
printf '\033[0;36m├%s┤\033[0m\n' "$(printf '─%.0s' $(seq 1 $BOX_W))"
printf '\033[0;36m│\033[0m \033[0;32m%-*s\033[0m \033[0;36m│\033[0m\n' $(( BOX_W - 2 )) "  http://localhost:${PORT}"
printf '\033[0;36m│\033[0m %-*s \033[0;36m│\033[0m\n' $(( BOX_W - 2 )) ""
printf '\033[0;36m│\033[0m \033[0;33m%-*s\033[0m \033[0;36m│\033[0m\n' $(( BOX_W - 2 )) "  Last run:  ${LAST}"
printf '\033[0;36m│\033[0m %-*s \033[0;36m│\033[0m\n' $(( BOX_W - 2 )) ""
printf '\033[0;36m│\033[0m \033[2m%-*s\033[0m \033[0;36m│\033[0m\n' $(( BOX_W - 2 )) "${SERVER_LINE}"
printf '\033[0;36m└%s┘\033[0m\n' "$(printf '─%.0s' $(seq 1 $BOX_W))"
printf '\n'
