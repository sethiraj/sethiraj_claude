#!/usr/bin/env bash
# collect-results.sh
# PostToolUse hook — fires after browser_close.
# Writes a timestamped results stub JSON so the dashboard agent
# has a file to pick up even if the skill did not persist one.

set -euo pipefail

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
RESULTS_FILE="bdd-results-${TIMESTAMP}.json"

# Only write if no results file already exists from this run
if ls bdd-results-*.json 1>/dev/null 2>&1; then
  echo "[bdd-collect] Results file already present — skipping stub creation."
  exit 0
fi

cat > "$RESULTS_FILE" <<EOF
{
  "_note": "Auto-generated stub by collect-results.sh. Replace with actual execution output.",
  "timestamp": "$TIMESTAMP",
  "features": []
}
EOF

echo "[bdd-collect] Results stub written: $RESULTS_FILE"
