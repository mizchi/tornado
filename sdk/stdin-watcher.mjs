// Background stdin watcher - reads user input and writes to interrupt file
// Spawned by the main process with stdio: ['inherit', 'pipe', 'inherit']
import { createInterface } from "readline";
import { appendFileSync, mkdirSync, writeFileSync } from "fs";

const INTERRUPT_FILE = ".tornado/interrupt.txt";

try {
  mkdirSync(".tornado", { recursive: true });
} catch {}
// Clear stale interrupt
try {
  writeFileSync(INTERRUPT_FILE, "", "utf-8");
} catch {}

const rl = createInterface({
  input: process.stdin,
  output: process.stderr,
  terminal: true,
  prompt: "",
});

rl.on("line", (line) => {
  const trimmed = line.trim();
  if (trimmed) {
    appendFileSync(INTERRUPT_FILE, trimmed + "\n", "utf-8");
    process.stderr.write(`\x1b[33m[USER] Queued: ${trimmed}\x1b[0m\n`);
  }
});

rl.on("close", () => process.exit(0));

// Exit when parent dies
process.on("disconnect", () => process.exit(0));
