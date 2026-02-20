import test from 'node:test';
import assert from 'node:assert/strict';

import { runAdapter } from './agent-runner.mjs';

test('runAdapter emits init events and mapped stream events in order', async () => {
  const events = [];
  const logs = [];

  const adapter = {
    tag: 'Mock',
    async start(opts) {
      assert.equal(opts.prompt, 'hello');
      return {
        sessionId: 's-1',
        initEvents: [{ type: 'system', subtype: 'init', session_id: 's-1' }],
        initLogs: ['booted'],
        stream: toAsync([{ kind: 'one' }, { kind: 'two' }]),
      };
    },
    emit(raw, sessionId) {
      return [{ event: { type: 'assistant', raw: raw.kind, session_id: sessionId }, log: `saw:${raw.kind}` }];
    },
  };

  await runAdapter(adapter, { prompt: 'hello' }, {
    write: (event) => events.push(event),
    log: (line) => logs.push(line),
  });

  assert.deepEqual(events, [
    { type: 'system', subtype: 'init', session_id: 's-1' },
    { type: 'assistant', raw: 'one', session_id: 's-1' },
    { type: 'assistant', raw: 'two', session_id: 's-1' },
  ]);
  assert.deepEqual(logs, ['booted', 'saw:one', 'saw:two']);
});

test('runAdapter supports log-only emissions', async () => {
  const events = [];
  const logs = [];

  const adapter = {
    tag: 'Mock',
    async start() {
      return {
        sessionId: 's-2',
        stream: toAsync([{ kind: 'tick' }]),
      };
    },
    emit() {
      return [{ log: 'only-log' }];
    },
  };

  await runAdapter(adapter, { prompt: 'x' }, {
    write: (event) => events.push(event),
    log: (line) => logs.push(line),
  });

  assert.deepEqual(events, []);
  assert.deepEqual(logs, ['only-log']);
});

async function* toAsync(values) {
  for (const value of values) {
    yield value;
  }
}
