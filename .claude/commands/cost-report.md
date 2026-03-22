Generate a cost report from the session cost log:

1. Read `.claude/.cost-log.jsonl`
2. Summarize: total sessions, sessions per day, average modified files per session
3. Estimate token usage based on session count
4. Recommend cost optimizations (model routing, batch operations)
