function truncate(value, max = 80) {
    return String(value || "").slice(0, max);
}
function collapseWhitespace(value) {
    return String(value || "").replace(/\s+/g, " ").trim();
}
function getItemId(item) {
    return typeof item?.id === "string" ? item.id : "";
}
export function getCodexItemId(item) {
    return getItemId(item);
}
function toolNameForEvent(item) {
    return String(item.server || item.server_name || item.tool || "mcp");
}
function formatMcpLabel(item) {
    const server = collapseWhitespace(item.server || item.server_name || "");
    const tool = collapseWhitespace(item.tool || "");
    if (server && tool)
        return `${server}.${tool}`;
    return server || tool || "mcp";
}
function formatMcpArgs(args) {
    if (!args)
        return "";
    const subagent = collapseWhitespace(args.subagent_type || args.agent_type || "");
    const description = collapseWhitespace(args.description || args.prompt || "");
    if (subagent && description)
        return `${subagent}: ${description}`;
    if (description)
        return description;
    const command = collapseWhitespace(args.command || args.cmd || "");
    if (command)
        return command;
    const path = collapseWhitespace(args.file_path || args.path || "");
    if (path)
        return path;
    const query = collapseWhitespace(args.query || args.q || "");
    if (query)
        return query;
    return truncate(JSON.stringify(args), 100);
}
function formatTodoSummary(items = []) {
    const total = items.length;
    const done = items.filter((item) => item.completed).length;
    const next = collapseWhitespace(items.find((item) => !item.completed)?.text || "");
    if (next)
        return `${done}/${total} done, next: ${truncate(next, 80)}`;
    return `${done}/${total} done`;
}
function lastNonEmptyLine(value) {
    const lines = String(value || "")
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean);
    return lines.length > 0 ? lines[lines.length - 1] : "";
}
function commandOutput(item) {
    return String(item.aggregated_output || item.output || "");
}
function commandFallback(item) {
    return typeof item.exit_code === "number"
        ? `exit_code=${item.exit_code}`
        : "";
}
function formatCommandLabel(item) {
    return `Bash(${truncate(collapseWhitespace(item.command || ""), 80)})`;
}
function extractMcpResultText(item) {
    if (typeof item.result === "string") {
        return item.result;
    }
    const content = item.result?.content || [];
    const text = content
        .map((block) => collapseWhitespace(block.text || ""))
        .filter(Boolean)
        .join(" ");
    if (text)
        return text;
    const structured = item.result?.structured_content;
    if (structured !== undefined) {
        return collapseWhitespace(JSON.stringify(structured));
    }
    if (typeof item.error === "string") {
        return item.error;
    }
    if (item.error?.message) {
        return item.error.message;
    }
    return "";
}
export function formatItemStartLog(item) {
    switch (item?.type) {
        case "command_execution":
            return formatCommandLabel(item);
        case "file_change": {
            const paths = (item.changes || []).map((change) => change.path).join(", ");
            return `Edit(${truncate(paths, 80)})`;
        }
        case "mcp_tool_call": {
            const toolName = toolNameForEvent(item);
            const argsSummary = formatMcpArgs(item.arguments);
            if (toolName === "Task" && argsSummary)
                return `Task(${truncate(argsSummary, 100)})`;
            return `MCP(${truncate(formatMcpLabel(item), 100)})`;
        }
        case "agent_message": {
            const text = collapseWhitespace(item.text || "");
            return text ? `Message: ${truncate(text, 100)}` : "Generating...";
        }
        case "reasoning": {
            const text = collapseWhitespace(item.text || "");
            return text ? `Reasoning: ${truncate(text, 100)}` : "Thinking...";
        }
        case "web_search":
            return `WebSearch(${truncate(collapseWhitespace(item.query || ""), 100)})`;
        case "todo_list":
            return `Todo: ${formatTodoSummary(item.items || [])}`;
        case "error":
            return `Error: ${truncate(collapseWhitespace(item.message || ""), 100)}`;
        default:
            return null;
    }
}
export function formatItemUpdateLog(item) {
    switch (item?.type) {
        case "command_execution": {
            const line = lastNonEmptyLine(commandOutput(item));
            if (line)
                return `Bash output: ${truncate(line, 100)}`;
            return `Bash running: ${truncate(collapseWhitespace(item.command || ""), 80)}`;
        }
        case "todo_list":
            return `Todo: ${formatTodoSummary(item.items || [])}`;
        case "reasoning": {
            const text = collapseWhitespace(item.text || "");
            return text ? `Reasoning: ${truncate(text, 100)}` : "Thinking...";
        }
        case "web_search":
            return `WebSearch(${truncate(collapseWhitespace(item.query || ""), 100)})`;
        case "mcp_tool_call":
            return `MCP running: ${truncate(formatMcpLabel(item), 100)}`;
        case "error":
            return `Error: ${truncate(collapseWhitespace(item.message || ""), 100)}`;
        default:
            return null;
    }
}
export function formatItemCompleteLog(item) {
    switch (item?.type) {
        case "command_execution": {
            const line = lastNonEmptyLine(commandOutput(item));
            if (line)
                return `${formatCommandLabel(item)} => ${truncate(line, 100)}`;
            const fallback = commandFallback(item);
            if (fallback)
                return `${formatCommandLabel(item)} => ${fallback}`;
            return formatCommandLabel(item);
        }
        case "file_change": {
            const summary = (item.changes || [])
                .map((change) => `${change.kind}: ${change.path}`)
                .join(", ");
            return summary ? `Edit: ${truncate(summary, 100)}` : "Edit: file changed";
        }
        case "mcp_tool_call": {
            const output = collapseWhitespace(extractMcpResultText(item));
            if (output)
                return `MCP(${truncate(formatMcpLabel(item), 80)}) => ${truncate(output, 100)}`;
            return `MCP(${truncate(formatMcpLabel(item), 80)})`;
        }
        case "agent_message": {
            const text = collapseWhitespace(item.text || "");
            return text ? `Message: ${truncate(text, 100)}` : "Message";
        }
        case "reasoning": {
            const text = collapseWhitespace(item.text || "");
            return text ? `Reasoning: ${truncate(text, 100)}` : "Thinking...";
        }
        case "web_search":
            return `WebSearch(${truncate(collapseWhitespace(item.query || ""), 100)})`;
        case "todo_list":
            return `Todo: ${formatTodoSummary(item.items || [])}`;
        case "error":
            return `Error: ${truncate(collapseWhitespace(item.message || ""), 100)}`;
        default:
            return null;
    }
}
export function normalizeItemStart(item) {
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
                _display: formatCommandLabel(item),
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
                _display: `Edit(${truncate(paths, 80)})`,
            };
        }
        case "mcp_tool_call":
            return {
                type: "assistant",
                message: {
                    content: [
                        {
                            type: "tool_use",
                            name: toolNameForEvent(item),
                            input: item.arguments || {},
                        },
                    ],
                },
                _display: formatItemStartLog(item) || `MCP(${formatMcpLabel(item)})`,
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
export function normalizeItemComplete(item) {
    switch (item?.type) {
        case "command_execution": {
            const output = commandOutput(item) || commandFallback(item);
            return {
                type: "tool_result",
                tool_name: "Bash",
                content: output,
                _display: formatItemCompleteLog(item) || `Bash: exit=${item.exit_code || 0}`,
            };
        }
        case "file_change": {
            const changes = item.changes || [];
            const summary = changes
                .map((change) => `${change.kind}: ${change.path}`)
                .join(", ");
            return {
                type: "tool_result",
                tool_name: "Edit",
                content: summary || "file changed",
                _display: formatItemCompleteLog(item) || `Edit: ${truncate(summary, 80)}`,
            };
        }
        case "mcp_tool_call": {
            const output = extractMcpResultText(item);
            return {
                type: "tool_result",
                tool_name: toolNameForEvent(item),
                content: output,
                _display: formatItemCompleteLog(item) || `MCP: ${truncate(output, 80)}`,
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
export function normalizeTurnCompleted(event, sessionId) {
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
export function normalizeTurnFailed(event, sessionId) {
    return {
        type: "result",
        subtype: "error",
        session_id: sessionId,
        is_error: true,
        result: event?.error?.message || "Turn failed",
    };
}
export function formatTurnCompletedLog(event) {
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
export function formatTurnFailedLog(event) {
    return `Failed: ${event?.error?.message || "unknown error"}`;
}
