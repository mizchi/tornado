///|
/// Run multiple agent tasks in parallel when the backend supports SDK fan-out.
pub fn run_parallel(
  backend : BoxedBackend,
  tasks : Array[(String, String)],
  on_output : (@types.AgentEvent) -> Unit,
  model? : String = "",
) -> Array[@types.AgentResult] {
  match backend.name() {
    "claude-code" => run_parallel_sdk_backend("claude", tasks, on_output, model)
    "codex" => run_parallel_sdk_backend("codex", tasks, on_output, model)
    _ => run_parallel_sequential(backend, tasks, on_output)
  }
}

///|
fn run_parallel_sequential(
  backend : BoxedBackend,
  tasks : Array[(String, String)],
  on_output : (@types.AgentEvent) -> Unit,
) -> Array[@types.AgentResult] {
  let results : Array[@types.AgentResult] = []
  for task in tasks {
    let (prompt, system_prompt) = task
    results.push(backend.run(prompt, system_prompt, on_output))
  }
  results
}

///|
fn run_parallel_sdk_backend(
  runner : String,
  tasks : Array[(String, String)],
  on_output : (@types.AgentEvent) -> Unit,
  model : String,
) -> Array[@types.AgentResult] {
  let opts : Map[String, Json] = {}
  opts["runner"] = runner.to_json()
  let task_opts : Array[Json] = []
  for task in tasks {
    let (prompt, system_prompt) = task
    let task_json : Map[String, Json] = {}
    task_json["prompt"] = prompt.to_json()
    if not(system_prompt.is_empty()) {
      task_json["systemPrompt"] = system_prompt.to_json()
    }
    if not(model.is_empty()) {
      task_json["model"] = model.to_json()
    }
    task_opts.push(Json::object(task_json))
  }
  opts["tasks"] = Json::array(task_opts)
  let raw_output = run_parallel_sdk(Json::object(opts).stringify())
  let sdk_output = match check_ffi_error(raw_output) {
    Err(err) => return replicate_failed_result(tasks.length(), err)
    Ok(output) => output
  }
  let parsed = @json.parse(sdk_output) catch {
    _ =>
      return replicate_failed_result(
        tasks.length(),
        "failed to parse parallel SDK output",
      )
  }
  match parsed {
    Array(results_json) => {
      let results : Array[@types.AgentResult] = []
      for entry in results_json {
        match entry {
          String(jsonl) => results.push(parse_jsonl_result(jsonl, on_output))
          _ =>
            results.push({
              content: "",
              status: @types.AgentStatus::Failed(
                "invalid parallel SDK result entry",
              ),
              error: Some("invalid parallel SDK result entry"),
              session_id: "",
            })
        }
      }
      while results.length() < tasks.length() {
        results.push({
          content: "",
          status: @types.AgentStatus::Failed("missing parallel SDK result"),
          error: Some("missing parallel SDK result"),
          session_id: "",
        })
      }
      results
    }
    _ =>
      replicate_failed_result(
        tasks.length(),
        "invalid parallel SDK output shape",
      )
  }
}

///|
fn replicate_failed_result(
  count : Int,
  err : String,
) -> Array[@types.AgentResult] {
  let results : Array[@types.AgentResult] = []
  for _ in 0..<count {
    results.push({
      content: "",
      status: @types.AgentStatus::Failed(err),
      error: Some(err),
      session_id: "",
    })
  }
  results
}

///|
fn failed_result(err : String) -> @types.AgentResult {
  {
    content: "",
    status: @types.AgentStatus::Failed(err),
    error: Some(err),
    session_id: "",
  }
}

///|
pub fn parse_jsonl_result(
  jsonl : String,
  on_output : (@types.AgentEvent) -> Unit,
) -> @types.AgentResult {
  match check_ffi_error(jsonl) {
    Err(err) => {
      on_output(
        @types.AgentEvent::StatusChange(@types.AgentStatus::Failed(err)),
      )
      return failed_result(err)
    }
    Ok(_) => ()
  }
  let buf = StringBuilder::new()
  let line_buf = OutputLineBuffer::new()
  let error_buf = StringBuilder::new()
  let mut has_error = false
  let mut captured_session_id = ""
  for line_view in jsonl.split("\n") {
    let line = line_view.to_string().trim().to_string()
    if line.is_empty() {
      continue
    }
    if parse_sdk_event_line(line, buf, line_buf, error_buf, on_output, fn(sid) {
        captured_session_id = sid
        on_output(@types.AgentEvent::SessionId(sid))
      }) {
      has_error = true
    }
  }
  line_buf.flush(fn(line) { on_output(@types.AgentEvent::OutputLine(line)) })
  let content = buf.to_string()
  if has_error {
    let err = error_buf.to_string()
    on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Failed(err)))
    {
      content,
      status: @types.AgentStatus::Failed(err),
      error: Some(err),
      session_id: captured_session_id,
    }
  } else {
    on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Completed))
    { content, status: Completed, error: None, session_id: captured_session_id }
  }
}

///|
pub fn parse_sdk_event_line(
  line : String,
  buf : StringBuilder,
  line_buf : OutputLineBuffer,
  error_buf : StringBuilder,
  on_output : (@types.AgentEvent) -> Unit,
  on_session_id : (String) -> Unit,
) -> Bool {
  let json = @json.parse(line) catch { _ => return false }
  match json {
    Object(map) =>
      parse_sdk_event_json(
        map, buf, line_buf, error_buf, on_output, on_session_id,
      )
    _ => false
  }
}

///|
fn parse_sdk_event_json(
  map : Map[String, Json],
  buf : StringBuilder,
  line_buf : OutputLineBuffer,
  error_buf : StringBuilder,
  on_output : (@types.AgentEvent) -> Unit,
  on_session_id : (String) -> Unit,
) -> Bool {
  match map.get("session_id") {
    Some(String(sid)) => if not(sid.is_empty()) { on_session_id(sid) }
    _ => ()
  }
  // Extract _tornado_ts and wrap on_output to prefix timestamped events
  let ts_on_output = match map.get("_tornado_ts") {
    Some(String(ts)) => wrap_output_with_ts(on_output, ts)
    _ => on_output
  }
  match map.get("type") {
    Some(String(event_type)) =>
      match event_type {
        "system" => parse_system_event(map, ts_on_output)
        "assistant" => parse_tool_calls(map, ts_on_output)
        "stream_event" =>
          match map.get("event") {
            Some(Object(event)) =>
              parse_sdk_stream_event(event, buf, line_buf, ts_on_output)
            _ => ()
          }
        "tool_result" => parse_tool_result(map, ts_on_output)
        "content_block_start" => parse_content_block_start(map, ts_on_output)
        "result" => {
          parse_sdk_result_event(map, ts_on_output)
          match map.get("is_error") {
            Some(True) => {
              match map.get("result") {
                Some(String(err_msg)) => error_buf.write_string(err_msg)
                _ => ()
              }
              return true
            }
            _ => ()
          }
        }
        _ => ()
      }
    _ => ()
  }
  false
}

///|
/// Wrap on_output to prefix Info and OutputLine events with [TS:HH:MM:SS]
fn wrap_output_with_ts(
  on_output : (@types.AgentEvent) -> Unit,
  ts : String,
) -> (@types.AgentEvent) -> Unit {
  fn(event) {
    match event {
      @types.AgentEvent::Info(msg) =>
        on_output(@types.AgentEvent::Info("[TS:\{ts}] \{msg}"))
      @types.AgentEvent::OutputLine(line) =>
        on_output(@types.AgentEvent::OutputLine("[TS:\{ts}] \{line}"))
      _ => on_output(event)
    }
  }
}

///|
fn parse_sdk_stream_event(
  event : Map[String, Json],
  buf : StringBuilder,
  line_buf : OutputLineBuffer,
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  match event.get("type") {
    Some(String(event_type)) =>
      match event_type {
        "content_block_start" => parse_content_block_start(event, on_output)
        "content_block_delta" =>
          match event.get("delta") {
            Some(Object(delta)) =>
              match delta.get("type") {
                Some(String("text_delta")) =>
                  match delta.get("text") {
                    Some(String(text)) => {
                      buf.write_string(text)
                      line_buf.push(text, fn(line) {
                        on_output(@types.AgentEvent::OutputLine(line))
                      })
                    }
                    _ => ()
                  }
                _ => ()
              }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
}
