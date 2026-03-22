#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: block force push commands (but allow --force-with-lease)

input="$(cat)"

command="$(echo "$input" | jq -r '.tool_input.command // empty')"

if [[ -z "${command:-}" ]]; then
  exit 0
fi

# Allow --force-with-lease (check before blocking --force)
# Remove --force-with-lease occurrences so they don't trigger the --force check
sanitized="$(echo "$command" | sed 's/--force-with-lease//g')"

# Check for git push --force or git push -f
if echo "$sanitized" | grep -qE 'git\s+push\b.*\s--force(\s|$)'; then
  echo "BLOCKED: git push --force is not allowed. Use --force-with-lease instead." >&2
  exit 2
fi

if echo "$sanitized" | grep -qE 'git\s+push\b.*\s-f(\s|$)'; then
  echo "BLOCKED: git push -f is not allowed. Use --force-with-lease instead." >&2
  exit 2
fi

exit 0
