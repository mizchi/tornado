#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: detect common secret patterns in written/edited files

input="$(cat)"

file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"

if [[ -z "${file_path:-}" ]]; then
  exit 0
fi

# Skip if file doesn't exist
if [[ ! -f "$file_path" ]]; then
  exit 0
fi

# Skip binary files
if file "$file_path" | grep -q 'binary'; then
  exit 0
fi

# Define secret patterns
findings=()

# AWS Access Key ID (AKIA...)
while IFS= read -r match; do
  findings+=("AWS Key: $match")
done < <(grep -nE 'AKIA[0-9A-Z]{16}' "$file_path" 2>/dev/null || true)

# OpenAI / Anthropic style API keys (sk-...)
while IFS= read -r match; do
  findings+=("API Key: $match")
done < <(grep -nE 'sk-[a-zA-Z0-9]{20,}' "$file_path" 2>/dev/null || true)

# Passwords in assignments
while IFS= read -r match; do
  findings+=("Password: $match")
done < <(grep -nEi 'password\s*=\s*["'"'"'][^"'"'"']+["'"'"']' "$file_path" 2>/dev/null || true)

# GitHub personal access tokens (ghp_...)
while IFS= read -r match; do
  findings+=("GitHub Token: $match")
done < <(grep -nE 'ghp_[a-zA-Z0-9]{36}' "$file_path" 2>/dev/null || true)

# Report findings
if [[ ${#findings[@]} -gt 0 ]]; then
  detail=""
  for f in "${findings[@]}"; do
    detail+="  - ${f}"$'\n'
  done

  ctx="WARNING: Possible secrets detected in ${file_path}:"$'\n'"${detail}Please review and remove any real credentials before committing."
  jq -n --arg ctx "$ctx" \
    '{"hookSpecificOutput": {"additionalContext": $ctx}}'
  exit 0
fi

exit 0
