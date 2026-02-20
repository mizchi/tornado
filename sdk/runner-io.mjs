export function writeJsonl(event, stream = process.stdout) {
    stream.write(`${JSON.stringify(event)}\n`);
}
export function createLogger(tag, stream = process.stderr) {
    return function log(message) {
        stream.write(`[${tag}] ${message}\n`);
    };
}
