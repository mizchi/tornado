import { Codex } from "@openai/codex-sdk";
import { formatTurnCompletedLog, formatTurnFailedLog, normalizeItemComplete, normalizeItemStart, normalizeTurnCompleted, normalizeTurnFailed, } from "./codex-normalizer.mjs";
export function createCodexAdapter(client = new Codex()) {
    return {
        tag: "Codex",
        async start(opts) {
            const threadOpts = {
                model: opts.model || undefined,
                workingDirectory: opts.cwd || process.cwd(),
                approvalPolicy: "never",
            };
            const logs = [];
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
        emit(raw, sessionId) {
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
function resumeThread(client, threadId, opts, logs) {
    logs.push(`Resuming thread: ${threadId}`);
    return client.resumeThread(threadId, opts);
}
function startThread(client, opts, logs) {
    logs.push("Starting new thread");
    return client.startThread(opts);
}
function emitItemStart(item) {
    const normalized = normalizeItemStart(item || {});
    if (!normalized)
        return [];
    const display = typeof normalized._display === "string"
        ? normalized._display
        : item?.type || "item.started";
    return [{ event: normalized, log: display }];
}
function emitItemComplete(item) {
    const normalized = normalizeItemComplete(item || {});
    if (!normalized)
        return [];
    const display = typeof normalized._display === "string"
        ? normalized._display
        : item?.type || "item.completed";
    return [{ event: normalized, log: `Done: ${display}` }];
}
