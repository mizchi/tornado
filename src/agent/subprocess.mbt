///| SubprocessBackend runs claude-code or codex as subprocess
pub struct SubprocessBackend {
  kind : @types.AgentKind
  model : String
  mut session_id : String
}

///| Create a new SubprocessBackend
pub fn SubprocessBackend::new(
  kind : @types.AgentKind,
  model? : String = "",
) -> SubprocessBackend {
  { kind, model, session_id: "" }
}

///| Get the current session id (set after first run)
pub fn SubprocessBackend::get_session_id(
  self : SubprocessBackend,
) -> String {
  self.session_id
}

///| Set session id for resume
pub fn SubprocessBackend::set_session_id(
  self : SubprocessBackend,
  session_id : String,
) -> Unit {
  self.session_id = session_id
}

///| AgentBackend implementation for SubprocessBackend
impl AgentBackend for SubprocessBackend with run(
  self,
  task,
  system_prompt,
  on_output,
) {
  on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Running))
  match self.kind {
    ClaudeCode => self.run_claude_code(task, system_prompt, on_output)
    Codex => self.run_codex(task, system_prompt, on_output)
    _ => self.run_claude_code(task, system_prompt, on_output)
  }
}

///| Run via Claude Agent SDK
fn SubprocessBackend::run_claude_code(
  self : SubprocessBackend,
  task : String,
  system_prompt : String,
  on_output : (@types.AgentEvent) -> Unit,
) -> @types.AgentResult {
  // Build SDK options as JSON
  let opts : Map[String, Json] = {}
  opts["prompt"] = task.to_json()
  if not(system_prompt.is_empty()) {
    opts["systemPrompt"] = system_prompt.to_json()
  }
  if not(self.model.is_empty()) {
    opts["model"] = self.model.to_json()
  }
  if not(self.session_id.is_empty()) {
    opts["sessionId"] = self.session_id.to_json()
  }
  let opts_json = Json::object(opts).stringify()
  on_output(
    @types.AgentEvent::Info(
      "Launching: claude-agent-sdk" +
      (if not(self.session_id.is_empty()) {
        " (resume: \{self.session_id})"
      } else {
        " (new session)"
      }),
    ),
  )
  // Run SDK via runner script
  let raw_output = run_claude_sdk(opts_json)
  if raw_output.has_prefix("ERROR:") {
    let err = raw_output
    on_output(
      @types.AgentEvent::StatusChange(@types.AgentStatus::Failed(err)),
    )
    return { content: "", status: @types.AgentStatus::Failed(err), error: Some(err) }
  }
  // Parse JSONL output
  let buf = StringBuilder::new()
  let mut has_error = false
  let error_buf = StringBuilder::new()
  let lines = raw_output.split("\n")
  for line_view in lines {
    let line = line_view.to_string().trim().to_string()
    if line.is_empty() {
      continue
    }
    self.parse_sdk_event(line, buf, error_buf, on_output) |> ignore
    // Check for error
    let json = @json.parse(line) catch { _ => continue }
    match json {
      Object(map) =>
        match map.get("type") {
          Some(String("result")) =>
            match map.get("is_error") {
              Some(True) => {
                has_error = true
                match map.get("result") {
                  Some(String(err_msg)) => error_buf.write_string(err_msg)
                  _ => ()
                }
              }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  let content = buf.to_string()
  if has_error {
    let err = error_buf.to_string()
    on_output(
      @types.AgentEvent::StatusChange(@types.AgentStatus::Failed(err)),
    )
    { content, status: @types.AgentStatus::Failed(err), error: Some(err) }
  } else {
    on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Completed))
    { content, status: Completed, error: None }
  }
}

///| Parse a single SDK JSONL event line
fn SubprocessBackend::parse_sdk_event(
  self : SubprocessBackend,
  line : String,
  buf : StringBuilder,
  _error_buf : StringBuilder,
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let json = @json.parse(line) catch { _ => return }
  match json {
    Object(map) => {
      // Extract session_id from any message
      match map.get("session_id") {
        Some(String(sid)) =>
          if not(sid.is_empty()) && self.session_id != sid {
            self.session_id = sid
            on_output(@types.AgentEvent::SessionId(sid))
          }
        _ => ()
      }
      match map.get("type") {
        Some(String(event_type)) =>
          match event_type {
            "system" => parse_system_event(map, on_output)
            "assistant" => parse_tool_calls(map, on_output)
            "stream_event" => {
              // SDK wraps Anthropic streaming events in stream_event
              match map.get("event") {
                Some(Object(event)) =>
                  self.parse_stream_event(event, buf, on_output)
                _ => ()
              }
            }
            "tool_result" => parse_tool_result(map, on_output)
            // CLI-compatible event types
            "content_block_start" =>
              parse_content_block_start(map, on_output)
            "result" => parse_sdk_result_event(map, on_output)
            _ => ()
          }
        _ => ()
      }
    }
    _ => ()
  }
}

///| Parse an SDK stream_event's inner Anthropic event
fn SubprocessBackend::parse_stream_event(
  _self : SubprocessBackend,
  event : Map[String, Json],
  buf : StringBuilder,
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  match event.get("type") {
    Some(String(event_type)) =>
      match event_type {
        "content_block_start" => parse_content_block_start(event, on_output)
        "content_block_delta" => {
          match event.get("delta") {
            Some(Object(delta)) =>
              match delta.get("type") {
                Some(String("text_delta")) =>
                  match delta.get("text") {
                    Some(String(text)) => {
                      buf.write_string(text)
                      on_output(@types.AgentEvent::OutputLine(text))
                    }
                    _ => ()
                  }
                _ => ()
              }
            _ => ()
          }
        }
        _ => ()
      }
    _ => ()
  }
}

///| Parse SDK result event (uses total_cost_usd instead of cost_usd)
fn parse_sdk_result_event(
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let subtype = match map.get("subtype") {
    Some(String(s)) => s
    _ => ""
  }
  let buf = StringBuilder::new()
  buf.write_string("Result: \{subtype}")
  // SDK uses total_cost_usd
  match map.get("total_cost_usd") {
    Some(Number(n, ..)) => buf.write_string(", cost=$\{n}")
    _ =>
      // Fallback to cost_usd (CLI format)
      match map.get("cost_usd") {
        Some(Number(n, ..)) => buf.write_string(", cost=$\{n}")
        _ => ()
      }
  }
  match map.get("duration_ms") {
    Some(Number(n, ..)) => {
      let secs = n / 1000.0
      buf.write_string(", duration=\{secs}s")
    }
    _ => ()
  }
  match map.get("duration_api_ms") {
    Some(Number(n, ..)) => {
      let secs = n / 1000.0
      buf.write_string(", api=\{secs}s")
    }
    _ => ()
  }
  match map.get("num_turns") {
    Some(Number(n, ..)) => buf.write_string(", turns=\{n.to_int()}")
    _ => ()
  }
  match map.get("usage") {
    Some(Object(usage)) => {
      let input_tokens = match usage.get("input_tokens") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let output_tokens = match usage.get("output_tokens") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      if input_tokens > 0 || output_tokens > 0 {
        buf.write_string(", tokens=\{input_tokens}in/\{output_tokens}out")
      }
    }
    _ => ()
  }
  // Extract final result text
  match map.get("result") {
    Some(String(result_text)) =>
      if not(result_text.is_empty()) {
        on_output(@types.AgentEvent::Info(buf.to_string()))
        return
      }
    _ => ()
  }
  on_output(@types.AgentEvent::Info(buf.to_string()))
}

///| Run via codex CLI (plain text output)
fn SubprocessBackend::run_codex(
  self : SubprocessBackend,
  task : String,
  _system_prompt : String,
  on_output : (@types.AgentEvent) -> Unit,
) -> @types.AgentResult {
  let args : Array[String] = []
  // If we have a session, use "resume" subcommand
  if not(self.session_id.is_empty()) {
    args.push("resume")
    args.push("--last")
  } else {
    args.push(task)
  }
  if not(self.model.is_empty()) {
    args.push("--model")
    args.push(self.model)
  }
  let args_json = Json::array(args.map(fn(s) { s.to_json() })).stringify()
  let codex_cmd = if not(self.session_id.is_empty()) {
    "codex resume --last"
  } else {
    "codex <task>"
  }
  on_output(@types.AgentEvent::Info("Launching: \{codex_cmd}"))
  let buf = StringBuilder::new()
  let mut has_error = false
  let error_buf = StringBuilder::new()
  @ffi.exec_stream(
    "codex",
    args_json,
    fn(line) {
      buf.write_string(line)
      buf.write_string("\n")
      on_output(@types.AgentEvent::OutputLine(line))
    },
    fn() {  },
    fn(err) {
      has_error = true
      error_buf.write_string(err)
      on_output(
        @types.AgentEvent::StatusChange(@types.AgentStatus::Failed(err)),
      )
    },
  )
  let content = buf.to_string()
  if has_error {
    let err = error_buf.to_string()
    { content, status: @types.AgentStatus::Failed(err), error: Some(err) }
  } else {
    // Mark as having a session for future resume
    if self.session_id.is_empty() {
      self.session_id = "codex-last"
    }
    on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Completed))
    { content, status: Completed, error: None }
  }
}

///| AgentBackend implementation for SubprocessBackend
impl AgentBackend for SubprocessBackend with name(self) {
  match self.kind {
    ClaudeCode => "claude-code"
    Codex => "codex"
    _ => "subprocess"
  }
}

///|
impl AgentBackend for SubprocessBackend with set_session_id(self, sid) {
  self.session_id = sid
}

///|
impl AgentBackend for SubprocessBackend with get_session_id(self) {
  self.session_id
}

///| Wrap in BoxedBackend for dynamic dispatch
pub fn SubprocessBackend::boxed(self : SubprocessBackend) -> BoxedBackend {
  BoxedBackend::new(self)
}
