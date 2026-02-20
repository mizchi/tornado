import { runAdapterFromArgv } from "./agent-runner.mjs";
import { createCodexAdapter } from "./codex-adapter.mjs";

await runAdapterFromArgv(createCodexAdapter());
