#!/usr/bin/env bash
# Stop hook (async): saves session state to .claude/.session-state.json
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo '.')"

STATE_FILE=".claude/.session-state.json"
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Collect modified files (staged + unstaged)
MODIFIED=$(git diff --name-only HEAD 2>/dev/null | head -50 | jq -R -s 'split("\n") | map(select(. != ""))')

# Write session state
cat > "$STATE_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "branch": "$BRANCH",
  "modified_files": $MODIFIED,
  "last_commit": "$(git log --format='%H %s' -1 2>/dev/null || echo 'none')"
}
EOF
