import test from 'node:test';
import assert from 'node:assert/strict';

import { createCodexAdapter } from './codex-adapter.mjs';

test('createCodexAdapter emits update logs for todo and command progress', () => {
  const adapter = createCodexAdapter(fakeClient());

  const todoStart = logsOf(adapter.emit({
    type: 'item.started',
    item: {
      id: 'todo-1',
      type: 'todo_list',
      items: [
        { text: 'inspect adapters', completed: true },
        { text: 'add failing tests', completed: false },
        { text: 'implement progress logs', completed: false },
      ],
    },
  }, 'thread-1'));
  assert.deepEqual(todoStart, [
    'Todo: 1/3 done, next: add failing tests',
  ]);

  const commandUpdate = logsOf(adapter.emit({
    type: 'item.updated',
    item: {
      id: 'cmd-1',
      type: 'command_execution',
      command: 'npm test',
      aggregated_output: 'running tests\nPASS sdk/codex-adapter.test.mjs\n',
      status: 'in_progress',
    },
  }, 'thread-1'));
  assert.deepEqual(commandUpdate, [
    'Bash output: PASS sdk/codex-adapter.test.mjs',
  ]);
});

test('createCodexAdapter formats web search and final command completion summaries', () => {
  const adapter = createCodexAdapter(fakeClient());

  const searchStart = logsOf(adapter.emit({
    type: 'item.started',
    item: {
      id: 'web-1',
      type: 'web_search',
      query: 'openai codex sdk item.updated',
    },
  }, 'thread-1'));
  assert.deepEqual(searchStart, [
    'WebSearch(openai codex sdk item.updated)',
  ]);

  const commandDone = logsOf(adapter.emit({
    type: 'item.completed',
    item: {
      id: 'cmd-1',
      type: 'command_execution',
      command: 'npm test',
      aggregated_output: 'PASS sdk/*.test.mjs\n',
      exit_code: 0,
      status: 'completed',
    },
  }, 'thread-1'));
  assert.deepEqual(commandDone, [
    'Done: Bash(npm test) => PASS sdk/*.test.mjs',
  ]);
});

function fakeClient() {
  return {
    startThread() {
      throw new Error('not used in emit-only tests');
    },
    resumeThread() {
      throw new Error('not used in emit-only tests');
    },
  };
}

function logsOf(emissions) {
  return emissions.flatMap((emission) => emission.log ? [emission.log] : []);
}
