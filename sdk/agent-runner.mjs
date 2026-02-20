import { createLogger, writeJsonl } from "./runner-io.mjs";
export async function runAdapter(adapter, opts, io) {
    const sink = io ?? createDefaultIO(adapter.tag);
    const started = await adapter.start(opts);
    for (const event of started.initEvents ?? []) {
        sink.write(event);
    }
    for (const line of started.initLogs ?? []) {
        sink.log(line);
    }
    for await (const raw of started.stream) {
        const emissions = adapter.emit(raw, started.sessionId);
        for (const emission of emissions) {
            if (emission.event !== undefined) {
                sink.write(emission.event);
            }
            if (emission.log) {
                sink.log(emission.log);
            }
        }
    }
}
export async function runAdapterFromArgv(adapter, argv = process.argv) {
    const arg = argv[2];
    if (!arg) {
        throw new Error("Missing runner options JSON in argv[2]");
    }
    const opts = JSON.parse(arg);
    await runAdapter(adapter, opts);
}
function createDefaultIO(tag) {
    const log = createLogger(tag);
    return {
        write(event) {
            writeJsonl(event);
        },
        log,
    };
}
