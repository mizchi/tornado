import test from 'node:test';
import assert from 'node:assert/strict';

import {
  formatTurnCompletedLog,
  formatTurnFailedLog,
  normalizeItemStart,
  normalizeItemComplete,
  normalizeTurnCompleted,
  normalizeTurnFailed,
} from './codex-normalizer.mjs';

test('normalizeItemStart: command_execution -> Bash tool_use event', () => {
  const event = normalizeItemStart({
    type: 'command_execution',
    command: 'npm test',
  });

  assert.equal(event.type, 'assistant');
  assert.equal(event.message.content[0].type, 'tool_use');
  assert.equal(event.message.content[0].name, 'Bash');
  assert.deepEqual(event.message.content[0].input, { command: 'npm test' });
  assert.equal(event._display, 'Bash(npm test)');
});

test('normalizeItemStart: Task-style subagent event keeps Task tool name', () => {
  const event = normalizeItemStart({
    type: 'mcp_tool_call',
    server_name: 'Task',
    arguments: { subagent_type: 'Explore', description: 'scan repo' },
  });

  assert.equal(event.type, 'assistant');
  assert.equal(event.message.content[0].type, 'tool_use');
  assert.equal(event.message.content[0].name, 'Task');
});

test('normalizeItemStart: unknown item type returns null', () => {
  const event = normalizeItemStart({ type: 'unknown_type' });
  assert.equal(event, null);
});

test('normalizeItemComplete: command_execution uses output if present', () => {
  const event = normalizeItemComplete({
    type: 'command_execution',
    output: 'ok',
    exit_code: 0,
  });

  assert.equal(event.type, 'tool_result');
  assert.equal(event.tool_name, 'Bash');
  assert.equal(event.content, 'ok');
});

test('normalizeItemComplete: command_execution falls back to exit code', () => {
  const event = normalizeItemComplete({
    type: 'command_execution',
    output: '',
    exit_code: 7,
  });

  assert.equal(event.content, 'exit_code=7');
});

test('normalizeItemComplete: Task result keeps tool_name Task', () => {
  const event = normalizeItemComplete({
    type: 'mcp_tool_call',
    server_name: 'Task',
    result: 'done',
  });

  assert.equal(event.type, 'tool_result');
  assert.equal(event.tool_name, 'Task');
  assert.equal(event.content, 'done');
});

test('normalizeTurnCompleted maps usage fields to tornado format', () => {
  const event = normalizeTurnCompleted(
    {
      usage: {
        input_tokens: 120,
        output_tokens: 30,
        cached_input_tokens: 77,
      },
    },
    'thread-1',
  );

  assert.equal(event.type, 'result');
  assert.equal(event.subtype, 'success');
  assert.equal(event.session_id, 'thread-1');
  assert.equal(event.usage.input_tokens, 120);
  assert.equal(event.usage.output_tokens, 30);
  assert.equal(event.usage.cache_read_input_tokens, 77);
  assert.equal(event.usage.cache_creation_input_tokens, 0);
});

test('normalizeTurnFailed creates error result event', () => {
  const event = normalizeTurnFailed(
    { error: { message: 'boom' } },
    'thread-9',
  );

  assert.equal(event.type, 'result');
  assert.equal(event.subtype, 'error');
  assert.equal(event.session_id, 'thread-9');
  assert.equal(event.is_error, true);
  assert.equal(event.result, 'boom');
});

test('formatTurnCompletedLog includes token and cache info', () => {
  const message = formatTurnCompletedLog({
    usage: {
      input_tokens: 10,
      output_tokens: 4,
      cached_input_tokens: 7,
    },
  });

  assert.equal(message, 'Result: success, 10in/4out, cached=7');
});

test('formatTurnFailedLog falls back to unknown error', () => {
  const message = formatTurnFailedLog({});
  assert.equal(message, 'Failed: unknown error');
});
