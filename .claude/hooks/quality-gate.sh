#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: type-check .mts files after Edit/Write
# Reads tool invocation JSON from stdin, runs tsc --noEmit for type checking.

# Read the full stdin JSON
input="$(cat)"

# Extract file path from tool_input.file_path or tool_input.path
file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"

# If no file path found, exit silently
if [[ -z "${file_path:-}" ]]; then
  exit 0
fi

# Only act on .mts files
case "$file_path" in
  *.mts)
    ;;
  *)
    exit 0
    ;;
esac

# Check if the file actually exists
if [[ ! -f "$file_path" ]]; then
  exit 0
fi

# Find the project root (where tsconfig.sdk.json lives)
project_root="$(cd "$(dirname "$file_path")" && git rev-parse --show-toplevel 2>/dev/null || echo "")"

if [[ -z "$project_root" ]] || [[ ! -f "$project_root/tsconfig.sdk.json" ]]; then
  exit 0
fi

# Run tsc --noEmit for type checking
tsc_output=""
if ! tsc_output="$(cd "$project_root" && npx tsc --noEmit -p tsconfig.sdk.json 2>&1)"; then
  jq -n --arg msg "TypeScript type-check errors:\n$tsc_output" \
    '{"hookSpecificOutput": {"additionalContext": $msg}}'
fi

exit 0
