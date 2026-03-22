#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: block git commands that skip verification hooks
# Blocks --no-verify, --no-gpg-sign, and bare -n in git commit context

input="$(cat)"

command="$(echo "$input" | jq -r '.tool_input.command // empty')"

if [[ -z "${command:-}" ]]; then
  exit 0
fi

# Check for --no-verify
if echo "$command" | grep -qE '\-\-no-verify'; then
  echo "BLOCKED: --no-verify is not allowed. Commit hooks must not be skipped." >&2
  exit 2
fi

# Check for --no-gpg-sign
if echo "$command" | grep -qE '\-\-no-gpg-sign'; then
  echo "BLOCKED: --no-gpg-sign is not allowed. GPG signing must not be bypassed." >&2
  exit 2
fi

# Check for -n flag in git commit context (short form of --no-verify)
# Match: git commit ... -n (but not other commands using -n)
if echo "$command" | grep -qE 'git\s+commit\b.*\s-n(\s|$)'; then
  echo "BLOCKED: git commit -n (--no-verify shorthand) is not allowed. Commit hooks must not be skipped." >&2
  exit 2
fi

exit 0
