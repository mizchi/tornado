import { query } from "@anthropic-ai/claude-agent-sdk";
import type {
  AdapterEmission,
  AdapterStartResult,
  AgentAdapter,
  RunnerOptions,
} from "./agent-adapter.mjs";

type ClaudeMessage = {
  type?: string;
  subtype?: string;
  model?: string;
  session_id?: string;
  status?: string | null;
  task_id?: string;
  task_type?: string;
  description?: string;
  summary?: string;
  tool_use_id?: string;
  tool_name?: string;
  elapsed_time_seconds?: number;
  event?: {
    type?: string;
    content_block?: { type?: string; name?: string };
  };
  message?: {
    content?: Array<{
      type?: string;
      name?: string;
      input?: unknown;
      text?: string;
    }>;
  };
  total_cost_usd?: number;
  duration_ms?: number;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
  };
  [key: string]: unknown;
};

type ClaudeLogState = {
  lastStatus: string | null | undefined;
  lastToolProgressById: Map<string, number>;
};

export function createClaudeAdapter(): AgentAdapter<ClaudeMessage> {
  const state: ClaudeLogState = {
    lastStatus: undefined,
    lastToolProgressById: new Map(),
  };

  return {
    tag: "Claude",
    async start(opts: RunnerOptions): Promise<AdapterStartResult<ClaudeMessage>> {
      const queryOpts = buildQueryOptions(opts);
      return {
        sessionId: opts.sessionId || "",
        stream: query({
          prompt: opts.prompt,
          options: queryOpts,
        }) as AsyncIterable<ClaudeMessage>,
      };
    },
    emit(raw: ClaudeMessage): readonly AdapterEmission[] {
      const emissions: AdapterEmission[] = [{ event: raw }];
      const logs = extractLogs(raw, state);
      for (const line of logs) {
        emissions.push({ log: line });
      }
      return emissions;
    },
  };
}

function buildQueryOptions(opts: RunnerOptions): Record<string, unknown> {
  const queryOptions: Record<string, unknown> = {
    includePartialMessages: true,
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    cwd: opts.cwd || process.cwd(),
  };

  if (opts.sessionId) queryOptions.resume = opts.sessionId;
  if (opts.model) queryOptions.model = opts.model;
  if (opts.systemPrompt) queryOptions.systemPrompt = opts.systemPrompt;

  return queryOptions;
}

function extractLogs(message: ClaudeMessage, state: ClaudeLogState): string[] {
  switch (message.type) {
    case "system":
      return extractSystemLog(message, state);
    case "stream_event":
      return extractStreamEventLog(message);
    case "assistant":
      return extractToolUseLog(message);
    case "tool_progress":
      return extractToolProgressLog(message, state);
    case "tool_use_summary":
      return extractToolUseSummaryLog(message);
    case "result":
      return [formatResultLog(message)];
    default:
      return [];
  }
}

function extractSystemLog(
  message: ClaudeMessage,
  state: ClaudeLogState,
): string[] {
  switch (message.subtype) {
    case "init":
      return [
        `Session init: model=${message.model || "unknown"}, session=${message.session_id || "new"}`,
      ];
    case "status":
      return extractStatusLog(message, state);
    case "task_started":
      return [formatTaskStartedLog(message)];
    case "task_notification":
      return [formatTaskNotificationLog(message)];
    default:
      return [];
  }
}

function extractStreamEventLog(message: ClaudeMessage): string[] {
  const event = message.event;
  if (event?.type !== "content_block_start") return [];

  const block = event.content_block;
  if (block?.type === "tool_use") {
    return [`Tool: ${block.name}`];
  }
  if (block?.type === "thinking") {
    return ["Thinking..."];
  }
  if (block?.type === "text") {
    return ["Generating..."];
  }
  return [];
}

function extractToolUseLog(message: ClaudeMessage): string[] {
  const logs: string[] = [];
  const content = message.message?.content;
  if (!Array.isArray(content)) return logs;

  for (const block of content) {
    if (block.type !== "tool_use") continue;
    const inputPreview = summarizeToolInput(block.name, block.input);
    logs.push(`${block.name}(${inputPreview})`);
  }

  return logs;
}

function extractStatusLog(
  message: ClaudeMessage,
  state: ClaudeLogState,
): string[] {
  const nextStatus = message.status === null
    ? null
    : typeof message.status === "string"
    ? message.status
    : undefined;

  if (nextStatus === undefined || nextStatus === state.lastStatus) {
    return [];
  }

  state.lastStatus = nextStatus;
  if (nextStatus === null) {
    return ["Status: ready"];
  }

  return [`Status: ${nextStatus}`];
}

function extractToolProgressLog(
  message: ClaudeMessage,
  state: ClaudeLogState,
): string[] {
  const elapsed = Math.floor(Number(message.elapsed_time_seconds || 0));
  if (elapsed <= 0) return [];

  const progressKey = message.tool_use_id || message.task_id || message.tool_name || "";
  const previous = state.lastToolProgressById.get(progressKey);
  if (!shouldEmitToolProgress(previous, elapsed)) {
    return [];
  }

  state.lastToolProgressById.set(progressKey, elapsed);
  return [`Tool progress: ${message.tool_name || "tool"} ${elapsed}s`];
}

function shouldEmitToolProgress(
  previous: number | undefined,
  elapsed: number,
): boolean {
  if (previous === elapsed) return false;
  if (elapsed <= 2) return true;
  return elapsed % 5 === 0;
}

function extractToolUseSummaryLog(message: ClaudeMessage): string[] {
  const summary = collapseWhitespace(message.summary || "");
  if (!summary) return [];
  return [`Summary: ${truncate(summary, 120)}`];
}

function formatTaskStartedLog(message: ClaudeMessage): string {
  const taskId = message.task_id || "?";
  const desc = collapseWhitespace(message.description || "");
  const taskType = collapseWhitespace(message.task_type || "");
  const label = taskType ? `${taskType}/${taskId}` : taskId;
  return `Task started [${label}]: ${truncate(desc || "started", 120)}`;
}

function formatTaskNotificationLog(message: ClaudeMessage): string {
  const taskId = message.task_id || "?";
  const status = collapseWhitespace(message.status || "completed");
  const summary = collapseWhitespace(message.summary || "");
  if (summary) {
    return `Task ${status} [${taskId}]: ${truncate(summary, 120)}`;
  }
  return `Task ${status} [${taskId}]`;
}

function summarizeToolInput(toolName: string | undefined, input: unknown): string {
  if (isRecord(input)) {
    if (toolName == "Task") {
      const subagent = firstString(input, ["subagent_type", "agent_type"]);
      const description = firstString(input, ["description", "prompt", "task"]);
      if (subagent && description) {
        return truncate(`${subagent}: ${description}`, 120);
      }
      if (description) return truncate(description, 120);
      if (subagent) return truncate(subagent, 120);
    }

    const command = firstString(input, ["command", "cmd"]);
    if (command) return truncate(command, 120);

    const path = firstString(input, ["file_path", "path"]);
    const pattern = firstString(input, ["pattern"]);
    const query = firstString(input, ["query", "q"]);
    const url = firstString(input, ["url"]);
    const description = firstString(input, ["description"]);

    if (path && pattern) return truncate(`${pattern} @ ${path}`, 120);
    if (path) return truncate(path, 120);
    if (pattern) return truncate(pattern, 120);
    if (query) return truncate(query, 120);
    if (url) return truncate(url, 120);
    if (description) return truncate(description, 120);
  }

  return truncate(JSON.stringify(input), 120);
}

function firstString(
  input: Record<string, unknown>,
  keys: readonly string[],
): string {
  for (const key of keys) {
    const value = input[key];
    if (typeof value === "string" && collapseWhitespace(value)) {
      return collapseWhitespace(value);
    }
  }
  return "";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function collapseWhitespace(value: unknown): string {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function truncate(value: unknown, max = 80): string {
  return String(value || "").slice(0, max);
}

function formatResultLog(message: ClaudeMessage): string {
  const parts = [`Result: ${message.subtype}`];

  if (message.total_cost_usd) {
    parts.push(`cost=$${message.total_cost_usd.toFixed(4)}`);
  }
  if (message.duration_ms) {
    parts.push(`${(message.duration_ms / 1000).toFixed(1)}s`);
  }
  if (message.usage) {
    const { input_tokens, output_tokens } = message.usage;
    if (input_tokens || output_tokens) {
      parts.push(`${input_tokens || 0}in/${output_tokens || 0}out`);
    }
  }

  return parts.join(", ");
}
