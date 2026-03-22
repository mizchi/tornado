#!/usr/bin/env bash
# Stop hook (async): logs session info for cost tracking
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo '.')"

LOG_FILE=".claude/.cost-log.jsonl"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
MOD_COUNT=$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')

echo "{\"ts\":\"$TIMESTAMP\",\"branch\":\"$BRANCH\",\"modified_files\":$MOD_COUNT}" >> "$LOG_FILE"
