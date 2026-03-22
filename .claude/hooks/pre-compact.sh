#!/usr/bin/env bash
# PreCompact hook: saves context before compaction
# Captures current branch, modified files, recent git log, and in-progress beads issues

set -euo pipefail

OUTPUT_FILE=".claude/.pre-compact-state.json"

# Current branch
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Modified files (staged + unstaged)
modified_files=$(git diff --name-only HEAD 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo "[]")

# Recent git log (5 commits)
recent_log=$(git log --oneline -5 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo "[]")

# In-progress beads issues
in_progress=$(bd list --status=in_progress 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo "[]")

# Timestamp
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write JSON
cat > "$OUTPUT_FILE" <<ENDJSON
{
  "timestamp": "$timestamp",
  "branch": "$branch",
  "modified_files": $modified_files,
  "recent_commits": $recent_log,
  "in_progress_issues": $in_progress
}
ENDJSON

echo "Pre-compact state saved to $OUTPUT_FILE"
