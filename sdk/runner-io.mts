export function writeJsonl(event: unknown, stream: NodeJS.WritableStream = process.stdout): void {
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
