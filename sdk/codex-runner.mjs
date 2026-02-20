// Codex SDK runner
// stdout: JSONL (structured data for MoonBit parser)
// stderr: human-readable progress (real-time via inherited fd)
import { Codex } from "@openai/codex-sdk";

const opts = JSON.parse(process.argv[2]);

function log(tag, msg) {
  process.stderr.write(`[${tag}] ${msg}\n`);
}

const codex = new Codex();

const threadOpts = {
  model: opts.model || undefined,
  workingDirectory: opts.cwd || process.cwd(),
  approvalPolicy: "never",
};

let thread;
if (opts.threadId) {
  log("Codex", `Resuming thread: ${opts.threadId}`);
  thread = codex.resumeThread(opts.threadId, threadOpts);
} else {
  log("Codex", "Starting new thread");
  thread = codex.startThread(threadOpts);
}

// Emit thread.started with thread_id
const initEvent = {
  type: "system",
  subtype: "init",
  session_id: thread.id,
  model: opts.model || "default",
};
process.stdout.write(JSON.stringify(initEvent) + "\n");
log("Codex", `Thread: ${thread.id}`);

const { events } = await thread.runStreamed(opts.prompt);

for await (const event of events) {
  // Write JSONL to stdout (normalized to tornado format)
  switch (event.type) {
    case "item.started": {
      const item = event.item;
      const normalized = normalizeItemStart(item);
      if (normalized) {
        process.stdout.write(JSON.stringify(normalized) + "\n");
        log("Codex", `${normalized._display || item.type}`);
      }
      break;
    }
    case "item.completed": {
      const item = event.item;
      const normalized = normalizeItemComplete(item);
      if (normalized) {
        process.stdout.write(JSON.stringify(normalized) + "\n");
        log("Codex", `Done: ${normalized._display || item.type}`);
      }
      break;
    }
    case "turn.completed": {
      const usage = event.usage || {};
      const resultEvent = {
        type: "result",
        subtype: "success",
        session_id: thread.id,
        usage: {
          input_tokens: usage.input_tokens || 0,
          output_tokens: usage.output_tokens || 0,
          cache_read_input_tokens: usage.cached_input_tokens || 0,
          cache_creation_input_tokens: 0,
        },
      };
      process.stdout.write(JSON.stringify(resultEvent) + "\n");
      const parts = ["Result: success"];
      if (usage.input_tokens || usage.output_tokens) {
        parts.push(`${usage.input_tokens || 0}in/${usage.output_tokens || 0}out`);
        if (usage.cached_input_tokens) {
          parts.push(`cached=${usage.cached_input_tokens}`);
        }
      }
      log("Codex", parts.join(", "));
      break;
    }
    case "turn.failed": {
      const errorEvent = {
        type: "result",
        subtype: "error",
        session_id: thread.id,
        is_error: true,
        result: event.error?.message || "Turn failed",
      };
      process.stdout.write(JSON.stringify(errorEvent) + "\n");
      log("Codex", `Failed: ${event.error?.message || "unknown error"}`);
      break;
    }
    case "item.updated": {
      // Intermediate updates - emit as info
      break;
    }
  }
}

// Normalize a started item to tornado event format
function normalizeItemStart(item) {
  switch (item.type) {
    case "command_execution":
      return {
        type: "assistant",
        message: {
          content: [{
            type: "tool_use",
            name: "Bash",
            input: { command: item.command || "" },
          }],
        },
        _display: `Bash(${(item.command || "").slice(0, 80)})`,
      };
    case "file_change": {
      const changes = item.changes || [];
      const paths = changes.map(c => c.path).join(", ");
      return {
        type: "assistant",
        message: {
          content: [{
            type: "tool_use",
            name: "Edit",
            input: { file_path: paths },
          }],
        },
        _display: `Edit(${paths.slice(0, 80)})`,
      };
    }
    case "mcp_tool_call":
      return {
        type: "assistant",
        message: {
          content: [{
            type: "tool_use",
            name: item.server_name || "mcp",
            input: item.arguments || {},
          }],
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

// Normalize a completed item to tornado event format
function normalizeItemComplete(item) {
  switch (item.type) {
    case "command_execution":
      return {
        type: "tool_result",
        tool_name: "Bash",
        content: item.output || `exit_code=${item.exit_code || 0}`,
        _display: `Bash: exit=${item.exit_code || 0}`,
      };
    case "file_change": {
      const changes = item.changes || [];
      const summary = changes.map(c => `${c.kind}: ${c.path}`).join(", ");
      return {
        type: "tool_result",
        tool_name: "Edit",
        content: summary || "file changed",
        _display: `Edit: ${summary.slice(0, 80)}`,
      };
    }
    case "mcp_tool_call":
      return {
        type: "tool_result",
        tool_name: item.server_name || "mcp",
        content: item.result || item.error || "",
        _display: `MCP: ${(item.result || item.error || "").slice(0, 80)}`,
      };
    case "agent_message": {
      const text = item.text || "";
      // Emit as output lines
      return {
        type: "assistant",
        message: {
          content: [{
            type: "text",
            text: text,
          }],
        },
        _display: `Message: ${text.slice(0, 80)}`,
      };
    }
    default:
      return null;
  }
}
