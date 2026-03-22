#!/usr/bin/env bash
set -euo pipefail

# Stop hook: check for console.log in modified JS/TS files (excluding tests)

# Collect modified files from both staged and unstaged changes
modified_files=$(
  {
    git diff --cached --name-only 2>/dev/null || true
    git diff --name-only 2>/dev/null || true
  } | sort -u
)

# Filter to JS/TS files, excluding test files
target_files=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  # Match .js, .mjs, .ts, .mts extensions
  case "$file" in
    *.test.mjs|*.test.js|*.test.ts|*.test.mts) continue ;;
    *.js|*.mjs|*.ts|*.mts) ;;
    *) continue ;;
  esac
  # Only check files that actually exist
  [[ -f "$file" ]] && target_files+=("$file")
done <<< "$modified_files"

# No target files to check
if [[ ${#target_files[@]} -eq 0 ]]; then
  exit 0
fi

# Search for console.log in target files
findings=()
for file in "${target_files[@]}"; do
  # Find lines with console.log (excluding comments)
  while IFS= read -r match; do
    findings+=("$file: $match")
  done < <(grep -n 'console\.log' "$file" 2>/dev/null | grep -v '^\s*//' || true)
done

# Report findings
if [[ ${#findings[@]} -gt 0 ]]; then
  detail=""
  for f in "${findings[@]}"; do
    detail+="  - ${f}\n"
  done

  ctx="console.log statements found in modified files:"$'\n'"${detail}Please remove or replace with proper logging before committing."
  jq -n --arg ctx "$ctx" \
    '{"hookSpecificOutput": {"additionalContext": $ctx}}'
  exit 0
fi

exit 0
