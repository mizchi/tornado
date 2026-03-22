#!/usr/bin/env bash
# Notification hook: logs when builds complete
# Reads stdin JSON, checks for build/test related content, appends to build log

set -euo pipefail

LOG_FILE=".claude/.build-log.jsonl"

# Read notification from stdin
input=$(cat)

# Check if notification contains build/test related content
if echo "$input" | grep -qiE '(build|test|compile|lint|check|coverage|format|fmt)'; then
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Extract a summary (first 200 chars of input, escaped for JSON)
  summary=$(echo "$input" | head -c 200 | jq -Rs . 2>/dev/null || echo '""')

  # Append build event
  echo "{\"timestamp\":\"$timestamp\",\"event\":\"build_notification\",\"summary\":$summary}" >> "$LOG_FILE"
fi
