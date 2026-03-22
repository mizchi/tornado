#!/usr/bin/env bash
set -euo pipefail

# Stop hook: enforce tests pass when SDK files are modified

# Collect modified SDK files from both staged and unstaged changes
sdk_modified=$(
  {
    git diff --cached --name-only 2>/dev/null || true
    git diff --name-only 2>/dev/null || true
  } | sort -u | grep -E '^sdk/.*\.(mts|mjs)$' || true
)

# No SDK files modified — nothing to do
if [[ -z "$sdk_modified" ]]; then
  exit 0
fi

# Run SDK tests with a 60-second timeout (portable, no coreutils timeout needed)
TIMEOUT_SEC=60
test_output=""
test_exit=0

# Use a temp file for output since we need to run in a subshell for timeout
_tmpout=$(mktemp)
trap 'rm -f "$_tmpout"' EXIT

shopt -s nullglob
_test_files=(sdk/*.test.mjs)
shopt -u nullglob
if [[ ${#_test_files[@]} -eq 0 ]]; then
  exit 0
fi

(
  node --test "${_test_files[@]}" >"$_tmpout" 2>&1
) &
_pid=$!

# Wait up to TIMEOUT_SEC seconds
_elapsed=0
while kill -0 "$_pid" 2>/dev/null; do
  if [[ $_elapsed -ge $TIMEOUT_SEC ]]; then
    kill -9 "$_pid" 2>/dev/null || true
    wait "$_pid" 2>/dev/null || true
    jq -n --arg ctx "SDK tests timed out after ${TIMEOUT_SEC} seconds. Please investigate slow or hanging tests." \
      '{"hookSpecificOutput": {"additionalContext": $ctx}}'
    exit 0
  fi
  sleep 1
  _elapsed=$((_elapsed + 1))
done

wait "$_pid" 2>/dev/null || test_exit=$?
test_output=$(<"$_tmpout")

# Tests failed
if [[ $test_exit -ne 0 ]]; then
  # Truncate output to last 80 lines to keep JSON manageable
  truncated=$(echo "$test_output" | tail -80)
  jq -n --arg ctx "$(printf "SDK tests failed (exit code %d). Modified SDK files:\n%s\n\nTest output (last 80 lines):\n%s" "$test_exit" "$sdk_modified" "$truncated")" \
    '{"hookSpecificOutput": {"additionalContext": $ctx}}'
  exit 0
fi

# Tests passed
exit 0
