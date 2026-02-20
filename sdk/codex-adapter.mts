import { Codex } from "@openai/codex-sdk";
import type {
  AdapterEmission,
  AdapterStartResult,
  AgentAdapter,
  RunnerOptions,
} from "./agent-adapter.mjs";
import {
  formatTurnCompletedLog,
  formatTurnFailedLog,
  normalizeItemComplete,
  normalizeItemStart,
  normalizeTurnCompleted,
  normalizeTurnFailed,
} from "./codex-normalizer.mjs";

type CodexThreadOptions = {
  model?: string;
  workingDirectory: string;
  approvalPolicy: "never";
};

type CodexThread = {
  id: string;
  runStreamed(prompt: string): Promise<{ events: AsyncIterable<CodexEvent> }>;
};

type CodexClient = {
  startThread(opts: CodexThreadOptions): CodexThread;
  resumeThread(threadId: string, opts: CodexThreadOptions): CodexThread;
};

type CodexItem = {
  type?: string;
  _display?: string;
  [key: string]: unknown;
};

type CodexEvent = {
  type?: string;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
    cached_input_tokens?: number;
  };
  error?: { message?: string };
  item?: CodexItem;
};

export function createCodexAdapter(
  client: CodexClient = new Codex() as unknown as CodexClient,
): AgentAdapter<CodexEvent> {
  return {
    tag: "Codex",
    async start(opts: RunnerOptions): Promise<AdapterStartResult<CodexEvent>> {
      const threadOpts: CodexThreadOptions = {
        model: opts.model || undefined,
        workingDirectory: opts.cwd || process.cwd(),
        approvalPolicy: "never",
      };

      const logs: string[] = [];
      const thread = opts.threadId
        ? resumeThread(client, opts.threadId, threadOpts, logs)
        : startThread(client, threadOpts, logs);

      logs.push(`Thread: ${thread.id}`);
      const run = await thread.runStreamed(opts.prompt);

      return {
        sessionId: thread.id,
        initEvents: [
          {
            type: "system",
            subtype: "init",
            session_id: thread.id,
            model: opts.model || "default",
          },
        ],
        initLogs: logs,
        stream: run.events,
      };
    },
    emit(raw: CodexEvent, sessionId: string): readonly AdapterEmission[] {
      switch (raw.type) {
        case "item.started":
          return emitItemStart(raw.item);
        case "item.completed":
          return emitItemComplete(raw.item);
        case "turn.completed": {
          const resultEvent = normalizeTurnCompleted(raw, sessionId);
          return [{ event: resultEvent, log: formatTurnCompletedLog(raw) }];
        }
        case "turn.failed": {
          const errorEvent = normalizeTurnFailed(raw, sessionId);
          return [{ event: errorEvent, log: formatTurnFailedLog(raw) }];
        }
        default:
          return [];
      }
    },
  };
}

function resumeThread(
  client: CodexClient,
  threadId: string,
  opts: CodexThreadOptions,
  logs: string[],
): CodexThread {
  logs.push(`Resuming thread: ${threadId}`);
  return client.resumeThread(threadId, opts);
}

function startThread(
  client: CodexClient,
  opts: CodexThreadOptions,
  logs: string[],
): CodexThread {
  logs.push("Starting new thread");
  return client.startThread(opts);
}

function emitItemStart(item: CodexItem | undefined): readonly AdapterEmission[] {
  const normalized = normalizeItemStart(item || {});
  if (!normalized) return [];
  const display = typeof normalized._display === "string"
    ? normalized._display
    : item?.type || "item.started";
  return [{ event: normalized, log: display }];
}

function emitItemComplete(item: CodexItem | undefined): readonly AdapterEmission[] {
  const normalized = normalizeItemComplete(item || {});
  if (!normalized) return [];
  const display = typeof normalized._display === "string"
    ? normalized._display
    : item?.type || "item.completed";
  return [{ event: normalized, log: `Done: ${display}` }];
}
