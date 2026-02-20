export type RunnerOptions = {
  prompt: string;
  cwd?: string;
  model?: string;
  systemPrompt?: string;
  sessionId?: string;
  threadId?: string;
};

export type AdapterEmission = {
  event?: unknown;
  log?: string;
};

export type AdapterStartResult<RawEvent> = {
  sessionId: string;
  stream: AsyncIterable<RawEvent>;
  initEvents?: readonly unknown[];
  initLogs?: readonly string[];
};

export type AdapterIO = {
  write(event: unknown): void;
  log(line: string): void;
};

export interface AgentAdapter<RawEvent> {
  readonly tag: string;
  start(opts: RunnerOptions): Promise<AdapterStartResult<RawEvent>>;
  emit(raw: RawEvent, sessionId: string): readonly AdapterEmission[];
}
