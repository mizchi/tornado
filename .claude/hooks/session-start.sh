#!/usr/bin/env bash
# SessionStart hook: outputs project context for new sessions
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo '.')"

# Detect last session date from git log
LAST_DATE=$(git log --format='%ai' -1 2>/dev/null | cut -d' ' -f1)
NOW=$(date +%Y-%m-%d)

echo "=== Tornado Session Context ==="
echo "Date: $NOW | Last commit: $LAST_DATE"
echo "Branch: $(git branch --show-current 2>/dev/null || echo 'detached')"

# Show recent changes since last session
if [ -n "$LAST_DATE" ] && [ "$LAST_DATE" != "$NOW" ]; then
  RECENT=$(git log --oneline --since="$LAST_DATE" 2>/dev/null | head -10)
  if [ -n "$RECENT" ]; then
    echo ""
    echo "Recent changes since $LAST_DATE:"
    echo "$RECENT"
  fi
fi

# Show uncommitted state
DIRTY=$(git status --porcelain 2>/dev/null | head -5)
if [ -n "$DIRTY" ]; then
  echo ""
  echo "Uncommitted changes:"
  echo "$DIRTY"
fi

echo "=== End Context ==="
