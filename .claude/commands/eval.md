Run evaluation harness to measure quality metrics:

1. Run `bash .claude/eval/run-eval.sh`
2. Report pass@1 results for each quality gate
3. Compare against previous runs if `.claude/eval/history.jsonl` exists
4. Suggest improvements for any failing gates
