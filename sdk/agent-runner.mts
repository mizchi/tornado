import type {
  AdapterIO,
  AgentAdapter,
  RunnerOptions,
} from "./agent-adapter.mjs";
import { createLogger, writeJsonl } from "./runner-io.mjs";

export async function runAdapter<RawEvent>(
  adapter: AgentAdapter<RawEvent>,
  opts: RunnerOptions,
  io?: AdapterIO,
): Promise<void> {
  const sink = io ?? createDefaultIO(adapter.tag);
  const started = await adapter.start(opts);

  for (const event of started.initEvents ?? []) {
    sink.write(event);
  }
  for (const line of started.initLogs ?? []) {
    sink.log(line);
  }

  for await (const raw of started.stream) {
    const emissions = adapter.emit(raw, started.sessionId);
    for (const emission of emissions) {
      if (emission.event !== undefined) {
        sink.write(emission.event);
      }
      if (emission.log) {
        sink.log(emission.log);
      }
    }
  }
}

export async function runAdapterFromArgv<RawEvent>(
  adapter: AgentAdapter<RawEvent>,
  argv: readonly string[] = process.argv,
): Promise<void> {
  const arg = argv[2];
  if (!arg) {
    throw new Error("Missing runner options JSON in argv[2]");
  }
  const opts = JSON.parse(arg) as RunnerOptions;
  await runAdapter(adapter, opts);
}

function createDefaultIO(tag: string): AdapterIO {
  const log = createLogger(tag);
  return {
    write(event) {
      writeJsonl(event);
    },
    log,
  };
}
