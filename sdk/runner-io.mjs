function nowTimestamp() {
  const d = new Date();
  const h = String(d.getHours()).padStart(2, "0");
  const m = String(d.getMinutes()).padStart(2, "0");
  const s = String(d.getSeconds()).padStart(2, "0");
  return `${h}:${m}:${s}`;
}
export function stampEvent(event) {
  if (event != null && typeof event === "object") {
    return { ...event, _tornado_ts: nowTimestamp() };
  }
  return event;
}
export function writeJsonl(event, stream = process.stdout) {
  stream.write(`${JSON.stringify(event)}\n`);
}
export function createLogger(tag, stream = process.stderr) {
  return function log(message) {
    stream.write(`[${tag}] ${message}\n`);
  };
}
