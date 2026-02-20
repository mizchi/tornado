type UnknownRecord = Record<string, unknown>;

type CodexItem = {
  type?: string;
  command?: string;
  changes?: Array<{ kind?: string; path?: string }>;
  server_name?: string;
  arguments?: UnknownRecord;
  output?: string;
  exit_code?: number;
  result?: string;
  error?: string;
  text?: string;
};

type CodexTurnUsage = {
  input_tokens?: number;
  output_tokens?: number;
  cached_input_tokens?: number;
};

type CodexTurnEvent = {
  usage?: CodexTurnUsage;
  error?: { message?: string };
};

function truncate(value: unknown, max = 80): string {
  return String(value || "").slice(0, max);
}

export function normalizeItemStart(item: CodexItem): UnknownRecord | null {
  switch (item?.type) {
    case "command_execution":
      return {
        type: "assistant",
        message: {
          content: [
            {
              type: "tool_use",
              name: "Bash",
              input: { command: item.command || "" },
            },
          ],
        },
        _display: `Bash(${truncate(item.command)})`,
      };
    case "file_change": {
      const changes = item.changes || [];
      const paths = changes.map((change) => change.path).join(", ");
      return {
        type: "assistant",
        message: {
          content: [
            {
              type: "tool_use",
              name: "Edit",
              input: { file_path: paths },
            },
          ],
        },
        _display: `Edit(${truncate(paths)})`,
      };
    }
    case "mcp_tool_call":
      return {
        type: "assistant",
        message: {
          content: [
            {
              type: "tool_use",
              name: item.server_name || "mcp",
              input: item.arguments || {},
            },
          ],
        },
        _display: `MCP(${item.server_name || "?"})`,
      };
    case "agent_message":
      return {
        type: "content_block_start",
        content_block: { type: "text" },
        _display: "Generating...",
      };
    case "reasoning":
      return {
        type: "content_block_start",
        content_block: { type: "thinking" },
        _display: "Thinking...",
      };
    default:
      return null;
  }
}

export function normalizeItemComplete(item: CodexItem): UnknownRecord | null {
  switch (item?.type) {
    case "command_execution":
      return {
        type: "tool_result",
        tool_name: "Bash",
        content: item.output || `exit_code=${item.exit_code || 0}`,
        _display: `Bash: exit=${item.exit_code || 0}`,
      };
    case "file_change": {
      const changes = item.changes || [];
      const summary = changes
        .map((change) => `${change.kind}: ${change.path}`)
        .join(", ");
      return {
        type: "tool_result",
        tool_name: "Edit",
        content: summary || "file changed",
        _display: `Edit: ${truncate(summary)}`,
      };
    }
    case "mcp_tool_call": {
      const output = item.result || item.error || "";
      return {
        type: "tool_result",
        tool_name: item.server_name || "mcp",
        content: output,
        _display: `MCP: ${truncate(output)}`,
      };
    }
    case "agent_message": {
      const text = item.text || "";
      return {
        type: "assistant",
        message: {
          content: [
            {
              type: "text",
              text,
            },
          ],
        },
        _display: `Message: ${truncate(text)}`,
      };
    }
    default:
      return null;
  }
}

export function normalizeTurnCompleted(
  event: CodexTurnEvent,
  sessionId: string,
): UnknownRecord {
  const usage = event?.usage || {};
  return {
    type: "result",
    subtype: "success",
    session_id: sessionId,
    usage: {
      input_tokens: usage.input_tokens || 0,
      output_tokens: usage.output_tokens || 0,
      cache_read_input_tokens: usage.cached_input_tokens || 0,
      cache_creation_input_tokens: 0,
    },
  };
}

export function normalizeTurnFailed(
  event: CodexTurnEvent,
  sessionId: string,
): UnknownRecord {
  return {
    type: "result",
    subtype: "error",
    session_id: sessionId,
    is_error: true,
    result: event?.error?.message || "Turn failed",
  };
}

export function formatTurnCompletedLog(event: CodexTurnEvent): string {
  const usage = event?.usage || {};
  const parts = ["Result: success"];
  if (usage.input_tokens || usage.output_tokens) {
    parts.push(`${usage.input_tokens || 0}in/${usage.output_tokens || 0}out`);
    if (usage.cached_input_tokens) {
      parts.push(`cached=${usage.cached_input_tokens}`);
    }
  }
  return parts.join(", ");
}

export function formatTurnFailedLog(event: CodexTurnEvent): string {
  return `Failed: ${event?.error?.message || "unknown error"}`;
}
