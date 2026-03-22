import test from "node:test";
import assert from "node:assert/strict";

import { runAdapter } from "./agent-runner.mjs";
import { stampEvent, writeJsonl } from "./runner-io.mjs";

test("runAdapter emits init events and mapped stream events in order", async () => {
  const events = [];
  const logs = [];

  const adapter = {
    tag: "Mock",
    async start(opts) {
      assert.equal(opts.prompt, "hello");
      return {
        sessionId: "s-1",
        initEvents: [{ type: "system", subtype: "init", session_id: "s-1" }],
        initLogs: ["booted"],
        stream: toAsync([{ kind: "one" }, { kind: "two" }]),
      };
    },
    emit(raw, sessionId) {
      return [
        {
          event: { type: "assistant", raw: raw.kind, session_id: sessionId },
          log: `saw:${raw.kind}`,
        },
      ];
    },
  };

  await runAdapter(
    adapter,
    { prompt: "hello" },
    {
      write: (event) => events.push(event),
      log: (line) => logs.push(line),
    },
  );

  // Strip dynamic _tornado_ts for structural comparison
  const stripped = events.map(({ _tornado_ts, ...rest }) => rest);
  assert.deepEqual(stripped, [
    { type: "system", subtype: "init", session_id: "s-1" },
    { type: "assistant", raw: "one", session_id: "s-1" },
    { type: "assistant", raw: "two", session_id: "s-1" },
  ]);
  // Verify each event carries _tornado_ts
  for (const event of events) {
    assert.match(event._tornado_ts, /^\d{2}:\d{2}:\d{2}$/);
  }
  assert.deepEqual(logs, ["booted", "saw:one", "saw:two"]);
});

test("runAdapter supports log-only emissions", async () => {
  const events = [];
  const logs = [];

  const adapter = {
    tag: "Mock",
    async start() {
      return {
        sessionId: "s-2",
        stream: toAsync([{ kind: "tick" }]),
      };
    },
    emit() {
      return [{ log: "only-log" }];
    },
  };

  await runAdapter(
    adapter,
    { prompt: "x" },
    {
      write: (event) => events.push(event),
      log: (line) => logs.push(line),
    },
  );

  assert.deepEqual(events, []);
  assert.deepEqual(logs, ["only-log"]);
});

// tornado-5r4: stampEvent adds _tornado_ts at call time
test("stampEvent adds _tornado_ts to each event object (tornado-5r4)", () => {
  const e1 = stampEvent({ type: "system", subtype: "init" });
  const e2 = stampEvent({ type: "assistant", message: {} });

  assert.ok(typeof e1._tornado_ts === "string", "_tornado_ts must be a string");
  assert.match(
    e1._tornado_ts,
    /^\d{2}:\d{2}:\d{2}$/,
    "_tornado_ts must be HH:MM:SS format",
  );
  assert.ok(typeof e2._tornado_ts === "string");
  assert.match(e2._tornado_ts, /^\d{2}:\d{2}:\d{2}$/);
});

// tornado-5r4: events stamped at different times get different timestamps
test("stampEvent captures distinct timestamps for delayed events (tornado-5r4)", async () => {
  const e1 = stampEvent({ type: "first" });
  // Wait enough for the second to differ by at least 1 second
  await new Promise((resolve) => setTimeout(resolve, 1100));
  const e2 = stampEvent({ type: "second" });

  assert.notEqual(
    e1._tornado_ts,
    e2._tornado_ts,
    "timestamps must differ for events 1s apart",
  );
});

// tornado-5r4: runAdapter preserves _tornado_ts through the pipeline
test("runAdapter stream events carry _tornado_ts from emit (tornado-5r4)", async () => {
  const events = [];

  const adapter = {
    tag: "Mock",
    async start() {
      return {
        sessionId: "s-ts",
        stream: toAsync([{ kind: "a" }, { kind: "b" }]),
      };
    },
    emit(raw) {
      return [{ event: { type: "test", kind: raw.kind } }];
    },
  };

  await runAdapter(
    adapter,
    { prompt: "x" },
    {
      write: (event) => events.push(event),
      log: () => {},
    },
  );

  for (const event of events) {
    assert.ok(
      typeof event._tornado_ts === "string",
      "streamed event must have _tornado_ts",
    );
    assert.match(event._tornado_ts, /^\d{2}:\d{2}:\d{2}$/);
  }
});

async function* toAsync(values) {
  for (const value of values) {
    yield value;
  }
}
