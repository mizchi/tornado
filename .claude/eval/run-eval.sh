#!/usr/bin/env bash
# Eval harness for tornado project — measures pass@1 for each quality gate
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PASS=0
FAIL=0
TOTAL=0
RESULTS=()

run_gate() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" > /dev/null 2>&1; then
    PASS=$((PASS + 1))
    RESULTS+=("PASS  $name")
  else
    FAIL=$((FAIL + 1))
    RESULTS+=("FAIL  $name")
  fi
}

echo "=== tornado eval harness ==="
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

run_gate "moon-fmt"         moon fmt --check
run_gate "moon-check"       moon check --target js
run_gate "build-sdk"        npm run -s build:sdk
run_gate "prettier"         npx prettier --check 'sdk/**/*.{mts,mjs}'
run_gate "node-tests"       node --test sdk/*.test.mjs
run_gate "moon-tests"       moon test --target js

echo "--- results ---"
for r in "${RESULTS[@]}"; do
  echo "  $r"
done
echo ""
echo "pass@1: $PASS/$TOTAL"
echo ""

# Append to history
HISTORY_FILE="$(git rev-parse --show-toplevel)/.claude/eval/history.jsonl"
echo "{\"date\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pass\":$PASS,\"total\":$TOTAL,\"fail\":$FAIL}" >> "$HISTORY_FILE"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
