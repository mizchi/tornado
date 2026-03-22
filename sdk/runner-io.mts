function nowTimestamp(): string {
  const d = new Date();
  const h = String(d.getHours()).padStart(2, "0");
  const m = String(d.getMinutes()).padStart(2, "0");
  const s = String(d.getSeconds()).padStart(2, "0");
  return `${h}:${m}:${s}`;
}

export function stampEvent(event: unknown): unknown {
  if (event != null && typeof event === "object") {
    return { ...event, _tornado_ts: nowTimestamp() };
  }
  return event;
}

export function writeJsonl(
  event: unknown,
  stream: NodeJS.WritableStream = process.stdout,
): void {
  stream.write(`${JSON.stringify(event)}\n`);
}

export function createLogger(
  tag: string,
  stream: NodeJS.WritableStream = process.stderr,
): (message: string) => void {
  return function log(message: string): void {
    stream.write(`[${tag}] ${message}\n`);
  };
}
