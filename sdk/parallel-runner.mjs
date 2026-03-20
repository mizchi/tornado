import { runAdapter } from "./agent-runner.mjs";
import { createClaudeAdapter } from "./claude-adapter.mjs";
import { createCodexAdapter } from "./codex-adapter.mjs";
const arg = process.argv[2];
if (!arg) {
    throw new Error("Missing parallel runner options JSON in argv[2]");
}
const input = JSON.parse(arg);
const adapter = createAdapter(input.runner);
const results = await Promise.allSettled(input.tasks.map(async (task) => collectTaskOutput(adapter, task)));
process.stdout.write(`${JSON.stringify(results.map(formatSettledResult))}\n`);
function createAdapter(runner) {
    switch (runner) {
        case "claude":
            return createClaudeAdapter();
        case "codex":
            return createCodexAdapter();
        default:
            throw new Error(`Unsupported runner: ${runner}`);
    }
}
async function collectTaskOutput(adapter, opts) {
    let buffer = "";
    const io = {
        write(event) {
            buffer += `${JSON.stringify(event)}\n`;
        },
        log() {
            // Suppress stderr logging for parallel result aggregation.
        },
    };
    await runAdapter(adapter, opts, io);
    return buffer;
}
function formatSettledResult(result) {
    if (result.status === "fulfilled") {
        return result.value;
    }
    return `ERROR: ${getErrorMessage(result.reason)}`;
}
function getErrorMessage(error) {
    if (error instanceof Error) {
        return error.message;
    }
    return String(error);
}
