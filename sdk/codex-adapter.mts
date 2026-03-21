import { Codex } from "@openai/codex-sdk";
import type {
  AdapterEmission,
  AdapterStartResult,
  AgentAdapter,
  RunnerOptions,
} from "./agent-adapter.mjs";
import {
  formatItemCompleteLog,
  formatItemStartLog,
  formatItemUpdateLog,
  getCodexItemId,
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
  id?: string;
  type?: string;
  command?: string;
  aggregated_output?: string;
  status?: string;
  server?: string;
  server_name?: string;
  tool?: string;
  query?: string;
  items?: Array<{ text?: string; completed?: boolean }>;
  _display?: string;
  [key: string]: unknown;
};

type CodexEvent = {
  type?: string;
  message?: string;
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
  const lastItemLogs = new Map<string, string>();

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
          return emitItemStart(raw.item, lastItemLogs);
        case "item.updated":
          return emitItemUpdate(raw.item, lastItemLogs);
        case "item.completed":
          return emitItemComplete(raw.item, lastItemLogs);
        case "turn.started":
          return [{ log: "Turn started" }];
        case "turn.completed": {
          const resultEvent = normalizeTurnCompleted(raw, sessionId);
          return [{ event: resultEvent, log: formatTurnCompletedLog(raw) }];
        }
        case "turn.failed": {
          const errorEvent = normalizeTurnFailed(raw, sessionId);
          return [{ event: errorEvent, log: formatTurnFailedLog(raw) }];
        }
        case "error":
          return raw.message ? [{ log: `Error: ${raw.message}` }] : [];
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

function emitItemStart(
  item: CodexItem | undefined,
  lastItemLogs: Map<string, string>,
): readonly AdapterEmission[] {
  const normalized = normalizeItemStart(item || {});
  const display = typeof normalized?._display === "string"
    ? normalized._display
    : formatItemStartLog(item || {}) || item?.type || "item.started";

  return buildItemEmissions(item, normalized, display, lastItemLogs);
}

function emitItemUpdate(
  item: CodexItem | undefined,
  lastItemLogs: Map<string, string>,
): readonly AdapterEmission[] {
  const display = formatItemUpdateLog(item || {});
  return buildItemEmissions(item, undefined, display, lastItemLogs);
}

function emitItemComplete(
  item: CodexItem | undefined,
  lastItemLogs: Map<string, string>,
): readonly AdapterEmission[] {
  const normalized = normalizeItemComplete(item || {});
  const display = typeof normalized?._display === "string"
    ? normalized._display
    : formatItemCompleteLog(item || {}) || item?.type || "item.completed";

  const emissions = buildItemEmissions(
    item,
    normalized,
    display ? `Done: ${display}` : null,
    lastItemLogs,
  );

  const itemId = getCodexItemId(item || {});
  if (itemId) {
    lastItemLogs.delete(itemId);
  }

  return emissions;
}

function buildItemEmissions(
  item: CodexItem | undefined,
  event: unknown,
  log: string | null | undefined,
  lastItemLogs: Map<string, string>,
): readonly AdapterEmission[] {
  const emissions: AdapterEmission[] = [];

  if (event !== undefined) {
    emissions.push({ event });
  }

  const itemId = getCodexItemId(item || {});
  if (log) {
    if (!itemId || lastItemLogs.get(itemId) !== log) {
      emissions.push({ log });
      if (itemId) {
        lastItemLogs.set(itemId, log);
      }
    }
  }

  return emissions;
}
