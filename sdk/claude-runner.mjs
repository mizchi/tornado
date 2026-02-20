// Claude Agent SDK runner
// stdout: JSONL (structured data for MoonBit parser)
// stderr: human-readable progress (real-time via inherited fd)
import { query } from "@anthropic-ai/claude-agent-sdk";

const opts = JSON.parse(process.argv[2]);

const queryOpts = {
  includePartialMessages: true,
  permissionMode: "bypassPermissions",
  allowDangerouslySkipPermissions: true,
  cwd: opts.cwd || process.cwd(),
};

if (opts.sessionId) queryOpts.resume = opts.sessionId;
if (opts.model) queryOpts.model = opts.model;
if (opts.systemPrompt) queryOpts.systemPrompt = opts.systemPrompt;

function log(tag, msg) {
  process.stderr.write(`[${tag}] ${msg}\n`);
}

let totalCost = 0;

for await (const message of query({
  prompt: opts.prompt,
  options: queryOpts,
})) {
  // Write structured JSONL to stdout
  process.stdout.write(JSON.stringify(message) + "\n");

  // Write human-readable progress to stderr (real-time)
  switch (message.type) {
    case "system":
      if (message.subtype === "init") {
        log("SDK", `Session init: model=${message.model || "unknown"}, session=${message.session_id || "new"}`);
      }
      break;

    case "stream_event": {
      const event = message.event;
      if (event?.type === "content_block_start") {
        const block = event.content_block;
        if (block?.type === "tool_use") {
          log("SDK", `Tool: ${block.name}`);
        } else if (block?.type === "thinking") {
          log("SDK", "Thinking...");
        } else if (block?.type === "text") {
          log("SDK", "Generating...");
        }
      }
      break;
    }

    case "assistant": {
      const content = message.message?.content;
      if (Array.isArray(content)) {
        for (const block of content) {
          if (block.type === "tool_use") {
            const inputPreview = JSON.stringify(block.input).slice(0, 100);
            log("SDK", `${block.name}(${inputPreview})`);
          }
        }
      }
      break;
    }

    case "result": {
      const parts = [`Result: ${message.subtype}`];
      if (message.total_cost_usd) {
        totalCost = message.total_cost_usd;
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
      log("SDK", parts.join(", "));
      break;
    }
  }
}
