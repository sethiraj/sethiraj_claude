#!/usr/bin/env bash
# validate-lighthouse.sh
# Checks if Lighthouse is installed. If not, installs it via npm for the current OS.

set -euo pipefail

echo "[end-user-perf] Validating Lighthouse installation..."

# ── Detect OS ────────────────────────────────────────────────────────────────
detect_os() {
  case "$(uname -s 2>/dev/null || echo "Windows")" in
    Linux*)   echo "linux"  ;;
    Darwin*)  echo "mac"    ;;
    CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
    *)
      # Fallback: check OS env var (Windows native)
      if [[ "${OS:-}" == "Windows_NT" ]]; then
        echo "windows"
      else
        echo "unknown"
      fi
      ;;
  esac
}

OS_TYPE=$(detect_os)
echo "[end-user-perf] Detected OS: ${OS_TYPE}"

# ── Resolve npm / node executables per OS ────────────────────────────────────
resolve_npm() {
  if [[ "${OS_TYPE}" == "windows" ]]; then
    # On Windows prefer npm.cmd which is on PATH after Node install
    if command -v npm.cmd &>/dev/null; then
      echo "npm.cmd"
    else
      echo "npm"
    fi
  else
    echo "npm"
  fi
}

resolve_lighthouse() {
  if [[ "${OS_TYPE}" == "windows" ]]; then
    if command -v lighthouse.cmd &>/dev/null; then
      echo "lighthouse.cmd"
    else
      echo "lighthouse"
    fi
  else
    echo "lighthouse"
  fi
}

LIGHTHOUSE_CMD=$(resolve_lighthouse)
NPM_CMD=$(resolve_npm)

# ── Check if Lighthouse is installed ─────────────────────────────────────────
check_lighthouse() {
  if command -v "${LIGHTHOUSE_CMD}" &>/dev/null; then
    VERSION=$("${LIGHTHOUSE_CMD}" --version 2>&1)
    # Validate that the output looks like a semver (e.g. 12.3.0)
    if echo "${VERSION}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+'; then
      echo "[end-user-perf] Lighthouse is installed. Version: ${VERSION}"
      return 0
    else
      echo "[end-user-perf] WARNING: Lighthouse returned unexpected output: ${VERSION}"
      return 1
    fi
  else
    return 1
  fi
}

# ── Install Lighthouse ────────────────────────────────────────────────────────
install_lighthouse() {
  echo "[end-user-perf] Lighthouse not found. Installing globally via npm..."

  case "${OS_TYPE}" in
    linux|mac)
      # Check if sudo is needed (non-root user with restricted global npm prefix)
      if [[ "$(id -u)" -ne 0 ]] && npm config get prefix 2>/dev/null | grep -q "^/usr"; then
        echo "[end-user-perf] Requires elevated permissions. Running: sudo npm install -g lighthouse"
        sudo "${NPM_CMD}" install -g lighthouse
      else
        echo "[end-user-perf] Running: ${NPM_CMD} install -g lighthouse"
        "${NPM_CMD}" install -g lighthouse
      fi
      ;;

    windows)
      echo "[end-user-perf] Running: ${NPM_CMD} install -g lighthouse"
      # On Windows, open a new elevated PowerShell session if needed
      if "${NPM_CMD}" install -g lighthouse 2>&1; then
        echo "[end-user-perf] Installation succeeded."
      else
        echo "[end-user-perf] npm install failed. Attempting via PowerShell with elevation..."
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
          "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command \"npm install -g lighthouse\"' -Verb RunAs -Wait"
      fi
      ;;

    *)
      echo "[end-user-perf] Unsupported OS. Please install Lighthouse manually:"
      echo "    npm install -g lighthouse"
      exit 1
      ;;
  esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
if check_lighthouse; then
  echo "[end-user-perf] Lighthouse validation passed. Proceeding with plugin."
  exit 0
else
  install_lighthouse

  # Re-validate after install
  echo "[end-user-perf] Re-validating after installation..."
  if check_lighthouse; then
    echo "[end-user-perf] Lighthouse installed successfully. Proceeding with plugin."
    exit 0
  else
    echo "[end-user-perf] ERROR: Lighthouse installation failed or binary not found on PATH."
    echo "    Please install manually: npm install -g lighthouse"
    exit 1
  fi
fi
