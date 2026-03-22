///|
test "MockBackend with default response" {
  let mock = @agent.MockBackend::new()
  let backend = mock.boxed()
  let events : Array[String] = []
  let result = backend.run("do something", "", fn(event) {
    match event {
      @types.AgentEvent::OutputLine(s) => events.push(s)
      _ => ()
    }
  })
  inspect(result.content, content="mock response")
  inspect(result.status, content="Completed")
  inspect(result.error, content="None")
  assert_true(events.length() == 1)
  inspect(events[0], content="mock response")
}

///|
test "MockBackend with custom responses" {
  let mock = @agent.MockBackend::new()
  mock.add_response("build", "building complete")
  mock.add_response("test", "tests passed")
  let backend = mock.boxed()
  let result1 = backend.run("build api", "", fn(_) {  })
  inspect(result1.content, content="building complete")
  let result2 = backend.run("test suite", "", fn(_) {  })
  inspect(result2.content, content="tests passed")
}

///|
test "MockBackend falls back to default" {
  let mock = @agent.MockBackend::new(default_response="fallback")
  let backend = mock.boxed()
  let result = backend.run("unknown task", "", fn(_) {  })
  inspect(result.content, content="fallback")
}

///|
test "MockBackend tracks call history" {
  let mock = @agent.MockBackend::new()
  let backend = mock.boxed()
  ignore(backend.run("task1", "prompt1", fn(_) {  }))
  ignore(backend.run("task2", "prompt2", fn(_) {  }))
  let history = mock.get_history()
  assert_true(history.length() == 2)
  let (t1, p1) = history[0]
  inspect(t1, content="task1")
  inspect(p1, content="prompt1")
  let (t2, p2) = history[1]
  inspect(t2, content="task2")
  inspect(p2, content="prompt2")
}

///|
test "MockBackend emits status events" {
  let mock = @agent.MockBackend::new()
  let backend = mock.boxed()
  let statuses : Array[String] = []
  ignore(
    backend.run("task", "", fn(event) {
      match event {
        @types.AgentEvent::StatusChange(s) => statuses.push(s.to_string())
        _ => ()
      }
    }),
  )
  assert_true(statuses.length() == 2)
  inspect(statuses[0], content="Running")
  inspect(statuses[1], content="Completed")
}

///|
test "FailingMockBackend returns failure" {
  let mock = @agent.FailingMockBackend::new(error_msg="oops")
  let backend = mock.boxed()
  let result = backend.run("task", "", fn(_) {  })
  inspect(result.content, content="")
  inspect(result.status, content="Failed(\"oops\")")
  inspect(result.error, content="Some(\"oops\")")
}

///|
test "FailingMockBackend emits failure events" {
  let mock = @agent.FailingMockBackend::new()
  let backend = mock.boxed()
  let statuses : Array[String] = []
  ignore(
    backend.run("task", "", fn(event) {
      match event {
        @types.AgentEvent::StatusChange(s) => statuses.push(s.to_string())
        _ => ()
      }
    }),
  )
  assert_true(statuses.length() == 2)
  inspect(statuses[0], content="Running")
  inspect(statuses[1], content="Failed(\"mock error\")")
}

///|
test "BoxedBackend wraps MockBackend" {
  let mock = @agent.MockBackend::new(default_response="boxed result")
  let boxed = mock.boxed()
  inspect(boxed.name(), content="mock")
  let result = boxed.run("task", "", fn(_) {  })
  inspect(result.content, content="boxed result")
}

///|
test "BoxedBackend wraps FailingMockBackend" {
  let mock = @agent.FailingMockBackend::new(error_msg="boxed error")
  let boxed = mock.boxed()
  inspect(boxed.name(), content="failing-mock")
  let result = boxed.run("task", "", fn(_) {  })
  inspect(result.status, content="Failed(\"boxed error\")")
}

///|
test "SubprocessBackend name via boxed" {
  let cc = @agent.SubprocessBackend::new(@types.AgentKind::ClaudeCode)
  let boxed = cc.boxed()
  inspect(boxed.name(), content="claude-code")
  let codex = @agent.SubprocessBackend::new(@types.AgentKind::Codex)
  let boxed2 = codex.boxed()
  inspect(boxed2.name(), content="codex")
}

///|
test "MockBackend name via boxed" {
  let mock = @agent.MockBackend::new()
  let boxed = mock.boxed()
  inspect(boxed.name(), content="mock")
}

///|
test "create_backend uses parseable planner mock response" {
  let backend = @agent.create_backend({
    id: "planner",
    kind: @types.AgentKind::Mock,
    role: @types.AgentRole::Planner,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  })
  let result = backend.run("plan milestone", "", fn(_) {  })
  inspect(result.content, content="WAVE 0:\n1. Mock planned task")
}

///|
test "run_parallel with MockBackend returns one result per task" {
  let mock = @agent.MockBackend::new()
  mock.add_response("task1", "result one")
  mock.add_response("task2", "result two")
  mock.add_response("task3", "result three")
  let boxed = mock.boxed()
  let results = @agent.run_parallel(
    boxed,
    [("task1", "sys1"), ("task2", "sys2"), ("task3", "sys3")],
    fn(_) {  },
  )
  assert_true(results.length() == 3)
  inspect(results[0].content, content="result one")
  inspect(results[1].content, content="result two")
  inspect(results[2].content, content="result three")
}

///|
test "run_parallel with FailingMockBackend returns all failures" {
  let mock = @agent.FailingMockBackend::new(error_msg="parallel failure")
  let boxed = mock.boxed()
  let results = @agent.run_parallel(
    boxed,
    [("task1", ""), ("task2", ""), ("task3", "")],
    fn(_) {  },
  )
  assert_true(results.length() == 3)
  inspect(results[0].status, content="Failed(\"parallel failure\")")
  inspect(results[1].status, content="Failed(\"parallel failure\")")
  inspect(results[2].status, content="Failed(\"parallel failure\")")
}

// ── parse_events.mbt tests ──────────────────────────────────

///|
/// Helper: collect events into categorized arrays
struct EventCollector {
  infos : Array[String]
  tool_calls : Array[(String, String)]
  tool_results : Array[(String, String)]
  sub_starts : Array[(String, String)]
  sub_ends : Array[String]
}

///|
fn EventCollector::new() -> EventCollector {
  { infos: [], tool_calls: [], tool_results: [], sub_starts: [], sub_ends: [] }
}

///|
fn EventCollector::handler(
  self : EventCollector,
) -> (@types.AgentEvent) -> Unit {
  fn(event) {
    match event {
      @types.AgentEvent::Info(msg) => self.infos.push(msg)
      @types.AgentEvent::ToolCall(name=n, input=i) =>
        self.tool_calls.push((n, i))
      @types.AgentEvent::ToolResult(name=n, output=o) =>
        self.tool_results.push((n, o))
      @types.AgentEvent::SubAgentStart(agent_type=t, task=d) =>
        self.sub_starts.push((t, d))
      @types.AgentEvent::SubAgentEnd(agent_type=t) => self.sub_ends.push(t)
      _ => ()
    }
  }
}

///|
/// Helper: parse a JSON string into a Map
fn json_map(s : String) -> Map[String, Json] {
  let json = @json.parse(s) catch { _ => panic() }
  match json {
    Object(m) => m
    _ => panic()
  }
}

// ── OutputLineBuffer ──

///|
test "OutputLineBuffer emits complete lines only" {
  let lb = @agent.OutputLineBuffer::new()
  let lines : Array[String] = []
  lb.push("TO", fn(line) { lines.push(line) })
  assert_true(lines.is_empty())
  lb.push("DOロード\n次", fn(line) { lines.push(line) })
  assert_true(lines.length() == 1)
  inspect(lines[0], content="TODOロード")
}

///|
test "OutputLineBuffer flush emits trailing partial line" {
  let lb = @agent.OutputLineBuffer::new()
  let lines : Array[String] = []
  lb.push("途中まで", fn(line) { lines.push(line) })
  assert_true(lines.is_empty())
  lb.flush(fn(line) { lines.push(line) })
  assert_true(lines.length() == 1)
  inspect(lines[0], content="途中まで")
}

// ── parse_tool_calls ──

///|
test "parse_tool_calls extracts tool_use blocks" {
  let ec = EventCollector::new()
  let s =
    #|{
    #|  "type": "assistant",
    #|  "message": {
    #|    "content": [
    #|      {"type": "tool_use", "name": "Read", "input": {"file": "foo.mbt"}}
    #|    ]
    #|  }
    #|}
  let map = json_map(s)
  @agent.parse_tool_calls(map, ec.handler())
  assert_true(ec.tool_calls.length() == 1)
  inspect(ec.tool_calls[0].0, content="Read")
  assert_true(ec.tool_calls[0].1.contains("foo.mbt"))
}

///|
test "parse_tool_calls detects Task subagent launch" {
  let ec = EventCollector::new()
  let s =
    #|{
    #|  "type": "assistant",
    #|  "message": {
    #|    "content": [
    #|      {"type": "tool_use", "name": "Task", "input": {"subagent_type": "Bash", "description": "run tests"}}
    #|    ]
    #|  }
    #|}
  let map = json_map(s)
  @agent.parse_tool_calls(map, ec.handler())
  assert_true(ec.tool_calls.length() == 1)
  inspect(ec.tool_calls[0].0, content="Task")
  // Should also emit SubAgentStart
  assert_true(ec.sub_starts.length() == 1)
  inspect(ec.sub_starts[0].0, content="Bash")
  inspect(ec.sub_starts[0].1, content="run tests")
}

///|
test "parse_tool_calls handles multiple blocks" {
  let ec = EventCollector::new()
  let s =
    #|{
    #|  "type": "assistant",
    #|  "message": {
    #|    "content": [
    #|      {"type": "text", "text": "some text"},
    #|      {"type": "tool_use", "name": "Bash", "input": {"cmd": "ls"}},
    #|      {"type": "tool_use", "name": "Read", "input": {"file": "a.txt"}}
    #|    ]
    #|  }
    #|}
  let map = json_map(s)
  @agent.parse_tool_calls(map, ec.handler())
  // text block is ignored, only tool_use blocks
  assert_true(ec.tool_calls.length() == 2)
  inspect(ec.tool_calls[0].0, content="Bash")
  inspect(ec.tool_calls[1].0, content="Read")
}

///|
test "parse_tool_calls handles missing message gracefully" {
  let ec = EventCollector::new()
  let s =
    #|{"type": "assistant"}
  let map = json_map(s)
  @agent.parse_tool_calls(map, ec.handler())
  assert_true(ec.tool_calls.is_empty())
}

///|
test "parse_tool_calls handles missing content array" {
  let ec = EventCollector::new()
  let s =
    #|{"type": "assistant", "message": {}}
  let map = json_map(s)
  @agent.parse_tool_calls(map, ec.handler())
  assert_true(ec.tool_calls.is_empty())
}

///|
test "parse_tool_calls defaults tool name to unknown" {
  let ec = EventCollector::new()
  let s =
    #|{
    #|  "type": "assistant",
    #|  "message": {
    #|    "content": [
    #|      {"type": "tool_use"}
    #|    ]
    #|  }
    #|}
  let map = json_map(s)
  @agent.parse_tool_calls(map, ec.handler())
  assert_true(ec.tool_calls.length() == 1)
  inspect(ec.tool_calls[0].0, content="unknown")
}

// ── parse_tool_result ──

///|
test "parse_tool_result with tool_name field" {
  let ec = EventCollector::new()
  let s =
    #|{"tool_name": "Bash", "content": "file list output"}
  let map = json_map(s)
  @agent.parse_tool_result(map, ec.handler())
  assert_true(ec.tool_results.length() == 1)
  inspect(ec.tool_results[0].0, content="Bash")
  inspect(ec.tool_results[0].1, content="file list output")
}

///|
test "parse_tool_result falls back to name field" {
  let ec = EventCollector::new()
  let s =
    #|{"name": "Read", "content": "file contents"}
  let map = json_map(s)
  @agent.parse_tool_result(map, ec.handler())
  assert_true(ec.tool_results.length() == 1)
  inspect(ec.tool_results[0].0, content="Read")
}

///|
test "parse_tool_result defaults to unknown when no name" {
  let ec = EventCollector::new()
  let s =
    #|{"content": "some output"}
  let map = json_map(s)
  @agent.parse_tool_result(map, ec.handler())
  assert_true(ec.tool_results.length() == 1)
  inspect(ec.tool_results[0].0, content="unknown")
}

///|
test "parse_tool_result stringifies non-string content" {
  let ec = EventCollector::new()
  let s =
    #|{"tool_name": "Bash", "content": {"result": 42}}
  let map = json_map(s)
  @agent.parse_tool_result(map, ec.handler())
  assert_true(ec.tool_results[0].1.contains("42"))
}

///|
test "parse_tool_result handles missing content" {
  let ec = EventCollector::new()
  let s =
    #|{"tool_name": "Bash"}
  let map = json_map(s)
  @agent.parse_tool_result(map, ec.handler())
  inspect(ec.tool_results[0].1, content="")
}

///|
test "parse_tool_result emits SubAgentEnd for Task tool" {
  let ec = EventCollector::new()
  let s =
    #|{"tool_name": "Task", "content": "agent done"}
  let map = json_map(s)
  @agent.parse_tool_result(map, ec.handler())
  assert_true(ec.tool_results.length() == 1)
  assert_true(ec.sub_ends.length() == 1)
  inspect(ec.sub_ends[0], content="Task")
}

///|
test "parse_tool_result does not emit SubAgentEnd for non-Task" {
  let ec = EventCollector::new()
  let s =
    #|{"tool_name": "Bash", "content": "ok"}
  let map = json_map(s)
  @agent.parse_tool_result(map, ec.handler())
  assert_true(ec.sub_ends.is_empty())
}

// ── parse_system_event ──

///|
test "parse_system_event init with model and tools" {
  let ec = EventCollector::new()
  let s =
    #|{"subtype": "init", "model": "claude-sonnet-4-20250514", "tools": [{"name": "Bash"}, {"name": "Read"}]}
  let map = json_map(s)
  @agent.parse_system_event(map, ec.handler())
  assert_true(ec.infos.length() == 1)
  assert_true(ec.infos[0].contains("claude-sonnet-4-20250514"))
  assert_true(ec.infos[0].contains("tools=2"))
}

///|
test "parse_system_event init with missing fields" {
  let ec = EventCollector::new()
  let s =
    #|{"subtype": "init"}
  let map = json_map(s)
  @agent.parse_system_event(map, ec.handler())
  assert_true(ec.infos.length() == 1)
  assert_true(ec.infos[0].contains("unknown"))
  assert_true(ec.infos[0].contains("tools=0"))
}

///|
test "parse_system_event ignores non-init subtypes" {
  let ec = EventCollector::new()
  let s =
    #|{"subtype": "other"}
  let map = json_map(s)
  @agent.parse_system_event(map, ec.handler())
  assert_true(ec.infos.is_empty())
}

///|
test "parse_system_event ignores missing subtype" {
  let ec = EventCollector::new()
  let s =
    #|{"model": "claude-sonnet-4-20250514"}
  let map = json_map(s)
  @agent.parse_system_event(map, ec.handler())
  assert_true(ec.infos.is_empty())
}

// ── parse_content_block_start ──

///|
test "parse_content_block_start tool_use" {
  let ec = EventCollector::new()
  let s =
    #|{"content_block": {"type": "tool_use", "name": "Bash"}}
  let map = json_map(s)
  @agent.parse_content_block_start(map, ec.handler())
  assert_true(ec.infos.length() == 1)
  inspect(ec.infos[0], content="Using tool: Bash")
}

///|
test "parse_content_block_start tool_use without name" {
  let ec = EventCollector::new()
  let s =
    #|{"content_block": {"type": "tool_use"}}
  let map = json_map(s)
  @agent.parse_content_block_start(map, ec.handler())
  assert_true(ec.infos.length() == 1)
  inspect(ec.infos[0], content="Using tool: unknown")
}

///|
test "parse_content_block_start thinking" {
  let ec = EventCollector::new()
  let s =
    #|{"content_block": {"type": "thinking"}}
  let map = json_map(s)
  @agent.parse_content_block_start(map, ec.handler())
  assert_true(ec.infos.length() == 1)
  inspect(ec.infos[0], content="Thinking...")
}

///|
test "parse_content_block_start text" {
  let ec = EventCollector::new()
  let s =
    #|{"content_block": {"type": "text"}}
  let map = json_map(s)
  @agent.parse_content_block_start(map, ec.handler())
  assert_true(ec.infos.length() == 1)
  inspect(ec.infos[0], content="Generating response...")
}

///|
test "parse_content_block_start ignores unknown type" {
  let ec = EventCollector::new()
  let s =
    #|{"content_block": {"type": "image"}}
  let map = json_map(s)
  @agent.parse_content_block_start(map, ec.handler())
  assert_true(ec.infos.is_empty())
}

///|
test "parse_content_block_start handles missing content_block" {
  let ec = EventCollector::new()
  let s =
    #|{"other_field": "value"}
  let map = json_map(s)
  @agent.parse_content_block_start(map, ec.handler())
  assert_true(ec.infos.is_empty())
}

// ── parse_sdk_result_event ──

///|
test "parse_sdk_result_event with full metrics" {
  let ec = EventCollector::new()
  let s =
    #|{
    #|  "type": "result",
    #|  "subtype": "success",
    #|  "total_cost_usd": 0.05,
    #|  "duration_ms": 12500,
    #|  "duration_api_ms": 8200,
    #|  "num_turns": 3,
    #|  "usage": {"input_tokens": 5000, "output_tokens": 1200}
    #|}
  let map = json_map(s)
  @agent.parse_sdk_result_event(map, ec.handler())
  assert_true(ec.infos.length() == 1)
  let info = ec.infos[0]
  assert_true(info.contains("Result: success"))
  assert_true(info.contains("cost=$"))
  assert_true(info.contains("duration="))
  assert_true(info.contains("api_total="))
  assert_true(info.contains("turns=3"))
  assert_true(info.contains("tokens=5000in/1200out"))
}

///|
test "parse_sdk_result_event falls back to cost_usd" {
  let ec = EventCollector::new()
  let s =
    #|{"type": "result", "cost_usd": 0.03}
  let map = json_map(s)
  @agent.parse_sdk_result_event(map, ec.handler())
  assert_true(ec.infos[0].contains("cost=$"))
}

///|
test "parse_sdk_result_event with minimal fields" {
  let ec = EventCollector::new()
  let s =
    #|{"type": "result"}
  let map = json_map(s)
  @agent.parse_sdk_result_event(map, ec.handler())
  assert_true(ec.infos.length() == 1)
  inspect(ec.infos[0], content="Result: ")
}

///|
test "parse_sdk_result_event omits zero tokens" {
  let ec = EventCollector::new()
  let s =
    #|{"type": "result", "usage": {"input_tokens": 0, "output_tokens": 0}}
  let map = json_map(s)
  @agent.parse_sdk_result_event(map, ec.handler())
  assert_true(not(ec.infos[0].contains("tokens=")))
}

///|
test "parse_sdk_result_event labels api time as cumulative (tornado-a2v)" {
  // Regression: when parallel API calls occur, duration_api_ms can exceed
  // duration_ms. The label must indicate it is a cumulative sum, not
  // wall-clock time, to avoid confusion.
  let ec = EventCollector::new()
  let s =
    #|{
    #|  "type": "result",
    #|  "subtype": "success",
    #|  "duration_ms": 145358,
    #|  "duration_api_ms": 190683
    #|}
  let map = json_map(s)
  @agent.parse_sdk_result_event(map, ec.handler())
  let info = ec.infos[0]
  // Must NOT use the ambiguous "api=" label
  assert_true(not(info.contains(", api=")))
  // Must use the explicit "api_total=" label
  assert_true(info.contains("api_total="))
}

// ── Codex stream_event text accumulation ──

///|
test "parse_sdk_event_line accumulates Codex text_delta in buf" {
  let buf = StringBuilder::new()
  let lb = @agent.OutputLineBuffer::new()
  let err_buf = StringBuilder::new()
  let ec = EventCollector::new()
  let line =
    #|{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Codex result content"}}}
  let _has_error = @agent.parse_sdk_event_line(
    line,
    buf,
    lb,
    err_buf,
    ec.handler(),
    fn(_sid) {  },
  )
  inspect(buf.to_string(), content="Codex result content")
}

// ── tornado-5r4: timestamp propagation from _tornado_ts ──

///|
test "tornado-5r4: _tornado_ts propagated into Info events" {
  let buf = StringBuilder::new()
  let lb = @agent.OutputLineBuffer::new()
  let err_buf = StringBuilder::new()
  let ec = EventCollector::new()
  let line =
    #|{"type":"system","subtype":"init","model":"claude-test","tools":[],"_tornado_ts":"14:30:45"}
  let _has_error = @agent.parse_sdk_event_line(
    line,
    buf,
    lb,
    err_buf,
    ec.handler(),
    fn(_sid) {  },
  )
  assert_true(ec.infos.length() == 1)
  assert_true(ec.infos[0].has_prefix("[TS:14:30:45] "))
}

///|
test "tornado-5r4: _tornado_ts propagated into OutputLine events" {
  let buf = StringBuilder::new()
  let lb = @agent.OutputLineBuffer::new()
  let err_buf = StringBuilder::new()
  let lines : Array[String] = []
  let line =
    #|{"type":"stream_event","_tornado_ts":"09:15:30","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hello world\n"}}}
  let _has_error = @agent.parse_sdk_event_line(
    line,
    buf,
    lb,
    err_buf,
    fn(event) {
      match event {
        @types.AgentEvent::OutputLine(s) => lines.push(s)
        _ => ()
      }
    },
    fn(_sid) {  },
  )
  assert_true(lines.length() == 1)
  assert_true(lines[0].has_prefix("[TS:09:15:30] "))
}

// ── check_ffi_error tests ──

///|
test "check_ffi_error returns Ok for normal string" {
  let result = @agent.check_ffi_error("hello world")
  inspect(result, content="Ok(\"hello world\")")
}

///|
test "check_ffi_error returns Err for ERROR: prefixed string" {
  let result = @agent.check_ffi_error("ERROR: file not found")
  inspect(result, content="Err(\"ERROR: file not found\")")
}

///|
test "check_ffi_error returns Ok for empty string" {
  let result = @agent.check_ffi_error("")
  inspect(result, content="Ok(\"\")")
}

///|
test "check_ffi_error returns Err for ERROR: with no space" {
  let result = @agent.check_ffi_error("ERROR:no space")
  inspect(result, content="Err(\"ERROR:no space\")")
}

///|
test "check_ffi_error returns Ok for string containing ERROR: in middle" {
  let result = @agent.check_ffi_error("some ERROR: in the middle")
  inspect(result, content="Ok(\"some ERROR: in the middle\")")
}

///|
test "tornado-5r4: backward compat without _tornado_ts" {
  let buf = StringBuilder::new()
  let lb = @agent.OutputLineBuffer::new()
  let err_buf = StringBuilder::new()
  let ec = EventCollector::new()
  let line =
    #|{"type":"system","subtype":"init","model":"claude-test","tools":[]}
  let _has_error = @agent.parse_sdk_event_line(
    line,
    buf,
    lb,
    err_buf,
    ec.handler(),
    fn(_sid) {  },
  )
  assert_true(ec.infos.length() == 1)
  assert_true(not(ec.infos[0].has_prefix("[TS:")))
}
