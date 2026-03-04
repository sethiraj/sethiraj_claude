#!/usr/bin/env bash
# scan-features.sh
# Scans the BDD features folder and injects discovered .feature files
# into the session context as environment output for the bdd-test-executor skill.
#
# Resolution order for the features directory:
#   1. BDD_FEATURES_DIR environment variable (already set)
#   2. CLAUDE_HOOK_INPUT  — parse "features folder: <path>" from the user prompt
#   3. Default            — ./features relative to current working directory

set -euo pipefail

# ── Helpers ────────────────────────────────────────────────────────────────────

log()  { echo "[bdd-scan] $*" >&2; }
fail() { echo "[bdd-scan] ERROR: $*" >&2; exit 1; }

normalize_path() {
  local p="$1"
  # Convert Windows backslashes to forward slashes (works under Git Bash / MSYS)
  echo "${p//\\//}"
}

# ── 1. Resolve features directory ──────────────────────────────────────────────

FEATURES_DIR=""

# Priority 1 — explicit env var
if [[ -n "${BDD_FEATURES_DIR:-}" ]]; then
  FEATURES_DIR="$(normalize_path "$BDD_FEATURES_DIR")"
  log "Using BDD_FEATURES_DIR: $FEATURES_DIR"
fi

# Priority 2 — parse from user prompt via CLAUDE_HOOK_INPUT
if [[ -z "$FEATURES_DIR" && -n "${CLAUDE_HOOK_INPUT:-}" ]]; then
  # Match patterns like:
  #   "features folder: /path/to/features"
  #   "feature files in C:\tests\features"
  #   "use features from ./features"
  EXTRACTED=$(echo "$CLAUDE_HOOK_INPUT" | \
    grep -oiE '(features?\s+(folder|dir(ectory)?|path|files?(\s+in)?)\s*[:]?\s*)(["\x27]?)([^\s"'\'']+)' | \
    grep -oE '[^ "'\'']+$' | head -1 || true)

  if [[ -n "$EXTRACTED" ]]; then
    FEATURES_DIR="$(normalize_path "$EXTRACTED")"
    log "Extracted features path from prompt: $FEATURES_DIR"
  fi
fi

# Priority 3 — default ./features
if [[ -z "$FEATURES_DIR" ]]; then
  FEATURES_DIR="./features"
  log "No features path specified — defaulting to: $FEATURES_DIR"
fi

# ── 2. Validate directory ───────────────────────────────────────────────────────

if [[ ! -d "$FEATURES_DIR" ]]; then
  # Emit a soft warning (non-blocking exit 0) so the skill can ask the user
  echo ""
  echo "⚠️  BDD Features Directory Not Found"
  echo "──────────────────────────────────────────────────────────"
  echo "  Path checked : $FEATURES_DIR"
  echo ""
  echo "  To specify your features folder, use one of:"
  echo "    • Set environment variable:  export BDD_FEATURES_DIR=/path/to/features"
  echo "    • Mention in your prompt:    'features folder: /path/to/features'"
  echo "    • Create default location:   mkdir -p ./features"
  echo "──────────────────────────────────────────────────────────"
  echo ""
  exit 0
fi

# ── 3. Scan for .feature files ──────────────────────────────────────────────────

mapfile -t FEATURE_FILES < <(find "$FEATURES_DIR" -type f -name "*.feature" | sort)

TOTAL=${#FEATURE_FILES[@]}

if [[ $TOTAL -eq 0 ]]; then
  echo ""
  echo "⚠️  No .feature files found in: $FEATURES_DIR"
  echo "  Ensure your Gherkin files have the '.feature' extension."
  echo ""
  exit 0
fi

# ── 4. Output discovered files as context ──────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            BDD FEATURES DISCOVERED                          ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf  "║  Directory : %-47s ║\n" "$FEATURES_DIR"
printf  "║  Found     : %-47s ║\n" "$TOTAL feature file(s)"
echo "╠══════════════════════════════════════════════════════════════╣"

for f in "${FEATURE_FILES[@]}"; do
  RELATIVE="${f#$FEATURES_DIR/}"
  # Count scenarios in the file
  SCENARIO_COUNT=$(grep -cE '^\s*(Scenario|Scenario Outline):' "$f" 2>/dev/null || echo "?")
  printf "║  📄 %-37s [%2s scenario(s)] ║\n" "$RELATIVE" "$SCENARIO_COUNT"
done

echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Export as env for downstream hooks/scripts in the same session
export BDD_FEATURES_DIR="$FEATURES_DIR"
export BDD_FEATURE_FILES="${FEATURE_FILES[*]}"
export BDD_FEATURE_COUNT="$TOTAL"

# Emit machine-readable block that the skill can parse
echo "BDD_SCAN_RESULT:"
echo "  dir: $FEATURES_DIR"
echo "  count: $TOTAL"
for f in "${FEATURE_FILES[@]}"; do
  echo "  file: $f"
done
echo ""
