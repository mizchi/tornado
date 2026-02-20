import { query } from "@anthropic-ai/claude-agent-sdk";
export function createClaudeAdapter() {
    return {
        tag: "Claude",
        async start(opts) {
            const queryOpts = buildQueryOptions(opts);
            return {
                sessionId: opts.sessionId || "",
                stream: query({
                    prompt: opts.prompt,
                    options: queryOpts,
                }),
            };
        },
        emit(raw) {
            const emissions = [{ event: raw }];
            const logs = extractLogs(raw);
            for (const line of logs) {
                emissions.push({ log: line });
            }
            return emissions;
        },
    };
}
function buildQueryOptions(opts) {
    const queryOptions = {
        includePartialMessages: true,
        permissionMode: "bypassPermissions",
        allowDangerouslySkipPermissions: true,
        cwd: opts.cwd || process.cwd(),
    };
    if (opts.sessionId)
        queryOptions.resume = opts.sessionId;
    if (opts.model)
        queryOptions.model = opts.model;
    if (opts.systemPrompt)
        queryOptions.systemPrompt = opts.systemPrompt;
    return queryOptions;
}
function extractLogs(message) {
    switch (message.type) {
        case "system":
            return extractSystemLog(message);
        case "stream_event":
            return extractStreamEventLog(message);
        case "assistant":
            return extractToolUseLog(message);
        case "result":
            return [formatResultLog(message)];
        default:
            return [];
    }
}
function extractSystemLog(message) {
    if (message.subtype !== "init")
        return [];
    return [
        `Session init: model=${message.model || "unknown"}, session=${message.session_id || "new"}`,
    ];
}
function extractStreamEventLog(message) {
    const event = message.event;
    if (event?.type !== "content_block_start")
        return [];
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
function extractToolUseLog(message) {
    const logs = [];
    const content = message.message?.content;
    if (!Array.isArray(content))
        return logs;
    for (const block of content) {
        if (block.type !== "tool_use")
            continue;
        const inputPreview = JSON.stringify(block.input).slice(0, 100);
        logs.push(`${block.name}(${inputPreview})`);
    }
    return logs;
}
function formatResultLog(message) {
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
