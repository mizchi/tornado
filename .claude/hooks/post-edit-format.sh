#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: auto-format JS/TS files after Edit/Write
# Reads tool invocation JSON from stdin, formats the edited file with prettier.

# Read the full stdin JSON
input="$(cat)"

# Extract file path from tool_input.file_path or tool_input.path
file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"

# If no file path found, exit silently
if [[ -z "${file_path:-}" ]]; then
  exit 0
fi

# Only act on JS/TS files
case "$file_path" in
  *.js|*.mjs|*.ts|*.mts)
    ;;
  *)
    exit 0
    ;;
esac

# Check if the file actually exists
if [[ ! -f "$file_path" ]]; then
  exit 0
fi

# Check if prettier is available
if ! command -v npx &>/dev/null; then
  exit 0
fi

# Run prettier --write on the file, capture any output
format_output=""
if ! format_output="$(npx prettier --write "$file_path" 2>&1)"; then
  # Formatting failed — report via hookSpecificOutput
  jq -n --arg msg "prettier formatting failed for $file_path: $format_output" \
    '{"hookSpecificOutput": {"additionalContext": $msg}}'
  exit 0
fi

# Check if there are still issues (run --check after --write)
check_output=""
if ! check_output="$(npx prettier --check "$file_path" 2>&1)"; then
  jq -n --arg msg "prettier: formatting issues remain in $file_path: $check_output" \
    '{"hookSpecificOutput": {"additionalContext": $msg}}'
fi

exit 0
