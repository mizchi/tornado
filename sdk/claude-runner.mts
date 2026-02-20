import { runAdapterFromArgv } from "./agent-runner.mjs";
import { createClaudeAdapter } from "./claude-adapter.mjs";

await runAdapterFromArgv(createClaudeAdapter());
