#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# check-node.sh
# SessionStart hook: verifies Node.js is installed; installs it if missing.
# Also runs `npm install` in the plugin directory if node_modules is absent.
# Runs on macOS, Linux, and Windows (Git Bash / WSL).
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BANNER="[api-test-runner]"
MIN_NODE_MAJOR=18

# ── Helper: print coloured output ─────────────────────────────────────────────
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
info()   { echo "$BANNER $*"; }

# ── Resolve PATH for common install locations ──────────────────────────────────
refresh_path() {
  # Windows (Git Bash) common Node paths
  for candidate in \
    "/c/Program Files/nodejs" \
    "/c/Program Files (x86)/nodejs" \
    "$HOME/AppData/Roaming/nvm/current" \
    "$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -1)/bin" \
    "/usr/local/bin" \
    "/usr/bin" \
    "$HOME/.local/bin"
  do
    [ -d "$candidate" ] && export PATH="$candidate:$PATH"
  done

  # Source nvm if present
  if [ -f "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
  fi
}

refresh_path

# ── Check if node meets minimum version ───────────────────────────────────────
node_ok() {
  if ! command -v node &>/dev/null; then return 1; fi
  local ver
  ver=$(node -e "process.stdout.write(String(process.version.split('.')[0].slice(1)))" 2>/dev/null || echo 0)
  [ "$ver" -ge "$MIN_NODE_MAJOR" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — Node.js check / install
# ─────────────────────────────────────────────────────────────────────────────

if node_ok; then
  green "$BANNER ✓ Node.js $(node --version) detected"
else
  yellow "$BANNER Node.js >= v${MIN_NODE_MAJOR} not found — attempting installation…"

  OS="$(uname -s 2>/dev/null || echo Unknown)"
  INSTALLED=0

  # ── nvm (cross-platform, highest priority) ──────────────────────────────────
  if command -v nvm &>/dev/null || [ -f "$HOME/.nvm/nvm.sh" ]; then
    source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
    if command -v nvm &>/dev/null; then
      info "Installing LTS via nvm…"
      nvm install --lts && nvm alias default node && INSTALLED=1
    fi
  fi

  # ── Windows (Git Bash) — delegate to PowerShell ────────────────────────────
  if [ "$INSTALLED" -eq 0 ] && \
     { [[ "$OS" == MINGW* ]] || [[ "$OS" == CYGWIN* ]] || [[ "$OS" == MSYS* ]]; }; then
    info "Windows detected — delegating to PowerShell installer…"
    PS_SCRIPT="${PLUGIN_ROOT}/scripts/check-node.ps1"
    if [ -f "$PS_SCRIPT" ]; then
      powershell.exe -ExecutionPolicy Bypass -File "$(cygpath -w "$PS_SCRIPT")" && INSTALLED=1
    fi
    refresh_path
  fi

  # ── macOS ───────────────────────────────────────────────────────────────────
  if [ "$INSTALLED" -eq 0 ] && [[ "$OS" == Darwin* ]]; then
    if command -v brew &>/dev/null; then
      info "Installing via Homebrew…"
      brew install node && INSTALLED=1
    else
      info "Homebrew not found. Installing Homebrew first…"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && \
        brew install node && INSTALLED=1
    fi
  fi

  # ── Debian / Ubuntu ─────────────────────────────────────────────────────────
  if [ "$INSTALLED" -eq 0 ] && command -v apt-get &>/dev/null; then
    info "Installing via apt (NodeSource LTS)…"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && \
      sudo apt-get install -y nodejs && INSTALLED=1
  fi

  # ── Fedora / RHEL / CentOS (dnf) ────────────────────────────────────────────
  if [ "$INSTALLED" -eq 0 ] && command -v dnf &>/dev/null; then
    info "Installing via dnf…"
    sudo dnf install -y nodejs && INSTALLED=1
  fi

  # ── CentOS / older RHEL (yum) ───────────────────────────────────────────────
  if [ "$INSTALLED" -eq 0 ] && command -v yum &>/dev/null; then
    info "Installing via yum (NodeSource LTS)…"
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - && \
      sudo yum install -y nodejs && INSTALLED=1
  fi

  # ── Arch Linux ───────────────────────────────────────────────────────────────
  if [ "$INSTALLED" -eq 0 ] && command -v pacman &>/dev/null; then
    info "Installing via pacman…"
    sudo pacman -Sy --noconfirm nodejs npm && INSTALLED=1
  fi

  # ── Alpine Linux ─────────────────────────────────────────────────────────────
  if [ "$INSTALLED" -eq 0 ] && command -v apk &>/dev/null; then
    info "Installing via apk…"
    sudo apk add --no-cache nodejs npm && INSTALLED=1
  fi

  refresh_path

  if node_ok; then
    green "$BANNER ✓ Node.js $(node --version) installed successfully"
  else
    red "$BANNER ✗ Could not install Node.js automatically."
    red "$BANNER   Please install Node.js v${MIN_NODE_MAJOR}+ from: https://nodejs.org"
    red "$BANNER   Then restart your terminal and try again."
    exit 1
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — Install npm dependencies if node_modules is missing
# ─────────────────────────────────────────────────────────────────────────────

PKG_JSON="${PLUGIN_ROOT}/package.json"
NODE_MODULES="${PLUGIN_ROOT}/node_modules"

if [ -f "$PKG_JSON" ] && [ ! -d "$NODE_MODULES" ]; then
  yellow "$BANNER node_modules not found — running npm install…"
  (cd "$PLUGIN_ROOT" && npm install --prefer-offline --no-audit --no-fund 2>&1) && \
    green "$BANNER ✓ Dependencies installed"
elif [ -f "$PKG_JSON" ] && [ -d "$NODE_MODULES" ]; then
  # Quick sanity-check: ensure playwright is present
  if [ ! -d "${NODE_MODULES}/playwright" ]; then
    yellow "$BANNER playwright missing — running npm install…"
    (cd "$PLUGIN_ROOT" && npm install --prefer-offline --no-audit --no-fund 2>&1) && \
      green "$BANNER ✓ Dependencies installed"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — Install Playwright browsers if needed
# ─────────────────────────────────────────────────────────────────────────────

PW_CACHE="${LOCALAPPDATA:-$HOME}/.cache/ms-playwright"
PW_INSTALLED="${NODE_MODULES}/.playwright-installed"

if [ -d "${NODE_MODULES}/playwright" ] && [ ! -f "$PW_INSTALLED" ]; then
  yellow "$BANNER Installing Playwright browser binaries (first-time setup)…"
  (cd "$PLUGIN_ROOT" && node node_modules/.bin/playwright install chromium 2>&1) && \
    touch "$PW_INSTALLED" && \
    green "$BANNER ✓ Playwright browsers ready"
fi

green "$BANNER ✓ Environment ready — api-test-runner is good to go"
