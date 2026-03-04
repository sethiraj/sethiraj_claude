#!/usr/bin/env bash
# validate-playwright.sh
# PreToolUse hook — fires before any playwright browser_navigate call.
# Ensures npx and @playwright/mcp are reachable before the session starts.

set -euo pipefail

log()  { echo "[bdd-playwright] $*" >&2; }
fail() { echo "[bdd-playwright] ERROR: $*" >&2; exit 1; }

# ── Check Node / npx ────────────────────────────────────────────────────────────

if ! command -v npx &>/dev/null; then
  fail "npx not found on PATH. Install Node.js (>=18) from https://nodejs.org and retry."
fi

NODE_VER=$(node --version 2>/dev/null || echo "unknown")
log "Node.js version: $NODE_VER"

# ── Check @playwright/mcp reachability ─────────────────────────────────────────

if npx --yes @playwright/mcp@latest --version &>/dev/null 2>&1; then
  log "@playwright/mcp is reachable via npx."
else
  echo ""
  echo "⚠️  @playwright/mcp could not be verified."
  echo "  The MCP server will still be launched via npx on first use."
  echo "  If you encounter issues, run:  npx @playwright/mcp@latest --version"
  echo ""
fi

exit 0
