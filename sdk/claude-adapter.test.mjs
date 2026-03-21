import test from 'node:test';
import assert from 'node:assert/strict';

import { createClaudeAdapter } from './claude-adapter.mjs';

test('createClaudeAdapter emits structured progress logs for Claude task lifecycle', () => {
  const adapter = createClaudeAdapter();

  const statusLogs = logsOf(adapter.emit({
    type: 'system',
    subtype: 'status',
    status: 'compacting',
    session_id: 's-1',
  }));
  assert.deepEqual(statusLogs, ['Status: compacting']);

  const taskStartLogs = logsOf(adapter.emit({
    type: 'system',
    subtype: 'task_started',
    task_id: 'task-1',
    task_type: 'Explore',
    description: 'scan the repository for agent event handlers',
    session_id: 's-1',
  }));
  assert.deepEqual(taskStartLogs, [
    'Task started [Explore/task-1]: scan the repository for agent event handlers',
  ]);

  const taskDoneLogs = logsOf(adapter.emit({
    type: 'system',
    subtype: 'task_notification',
    task_id: 'task-1',
    status: 'completed',
    summary: 'identified Claude/Codex adapter bottlenecks',
    session_id: 's-1',
  }));
  assert.deepEqual(taskDoneLogs, [
    'Task completed [task-1]: identified Claude/Codex adapter bottlenecks',
  ]);
});

test('createClaudeAdapter summarizes tool input and throttles tool progress noise', () => {
  const adapter = createClaudeAdapter();

  const toolLogs = logsOf(adapter.emit({
    type: 'assistant',
    message: {
      content: [
        {
          type: 'tool_use',
          name: 'Bash',
          input: { command: 'npm test -- --watch=false' },
        },
        {
          type: 'tool_use',
          name: 'Task',
          input: {
            subagent_type: 'Explore',
            description: 'inspect codex item.updated events',
          },
        },
      ],
    },
    session_id: 's-1',
  }));
  assert.deepEqual(toolLogs, [
    'Bash(npm test -- --watch=false)',
    'Task(Explore: inspect codex item.updated events)',
  ]);

  const progress1 = logsOf(adapter.emit({
    type: 'tool_progress',
    tool_use_id: 'tool-1',
    tool_name: 'Bash',
    elapsed_time_seconds: 1,
    session_id: 's-1',
  }));
  assert.deepEqual(progress1, ['Tool progress: Bash 1s']);

  const progress3 = logsOf(adapter.emit({
    type: 'tool_progress',
    tool_use_id: 'tool-1',
    tool_name: 'Bash',
    elapsed_time_seconds: 3,
    session_id: 's-1',
  }));
  assert.deepEqual(progress3, []);

  const progress5 = logsOf(adapter.emit({
    type: 'tool_progress',
    tool_use_id: 'tool-1',
    tool_name: 'Bash',
    elapsed_time_seconds: 5,
    session_id: 's-1',
  }));
  assert.deepEqual(progress5, ['Tool progress: Bash 5s']);
});

function logsOf(emissions) {
  return emissions.flatMap((emission) => emission.log ? [emission.log] : []);
}
