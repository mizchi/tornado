import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
export const { nowTimestamp } = require("./now-timestamp.cjs");
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
