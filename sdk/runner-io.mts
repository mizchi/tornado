import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
export const {
  nowTimestamp,
}: { nowTimestamp: () => string } = require("./now-timestamp.cjs");

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
