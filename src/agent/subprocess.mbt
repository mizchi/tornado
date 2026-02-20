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

///| Run via claude CLI with session management
fn SubprocessBackend::run_claude_code(
  self : SubprocessBackend,
  task : String,
  system_prompt : String,
  on_output : (@types.AgentEvent) -> Unit,
) -> @types.AgentResult {
  // Build args directly to support --session-id / --continue
  let args : Array[String] = [
    "-p", task, "--output-format", "stream-json", "--verbose",
  ]
  if not(system_prompt.is_empty()) {
    args.push("--system-prompt")
    args.push(system_prompt)
  }
  if not(self.model.is_empty()) {
    args.push("--model")
    args.push(self.model)
  }
  // Session management: --continue to resume previous session context
  if not(self.session_id.is_empty()) {
    args.push("--resume")
    args.push(self.session_id)
  }
  let args_json = Json::array(args.map(fn(s) { s.to_json() }))
  // Log the command being launched
  let cmd_preview = if not(self.session_id.is_empty()) {
    "claude -p <task> --output-format stream-json --verbose --resume \{self.session_id}"
  } else {
    "claude -p <task> --output-format stream-json --verbose"
  }
  on_output(@types.AgentEvent::Info("Launching: \{cmd_preview}"))
  let buf = StringBuilder::new()
  let mut has_error = false
  let error_buf = StringBuilder::new()
  @ffi.exec_stream(
    "claude",
    args_json.stringify(),
    fn(line) {
      // Parse text/error from JSONL
      match @claude_code.parse_claude_code_line(line) {
        Some(event) =>
          match event {
            TextDelta(s) => {
              buf.write_string(s)
              on_output(@types.AgentEvent::OutputLine(s))
            }
            Error(msg) => {
              has_error = true
              error_buf.write_string(msg)
              on_output(
                @types.AgentEvent::StatusChange(
                  @types.AgentStatus::Failed(msg),
                ),
              )
            }
            _ => ()
          }
        None => ()
      }
      // Parse tool calls and session_id from raw JSONL
      self.parse_jsonl_events(line, on_output)
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
    on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Completed))
    { content, status: Completed, error: None }
  }
}

///| Parse JSONL events: session_id and tool calls
fn SubprocessBackend::parse_jsonl_events(
  self : SubprocessBackend,
  line : String,
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let json = @json.parse(line) catch { _ => return }
  match json {
    Object(map) => {
      // Extract session_id
      match map.get("session_id") {
        Some(String(sid)) =>
          if not(sid.is_empty()) && self.session_id != sid {
            self.session_id = sid
            on_output(@types.AgentEvent::SessionId(sid))
          }
        _ => ()
      }
      // Extract events by type
      match map.get("type") {
        Some(String(event_type)) =>
          match event_type {
            "system" => self.parse_system_event(map, on_output)
            "assistant" => self.parse_tool_calls(map, on_output)
            "content_block_start" =>
              self.parse_content_block_start(map, on_output)
            "tool_result" => self.parse_tool_result(map, on_output)
            "result" => self.parse_result_event(map, on_output)
            _ => ()
          }
        _ => ()
      }
    }
    _ => ()
  }
}

///| Parse tool_use blocks from assistant message content
fn SubprocessBackend::parse_tool_calls(
  _self : SubprocessBackend,
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let message = match map.get("message") {
    Some(Object(m)) => m
    _ => return
  }
  let content = match message.get("content") {
    Some(Array(arr)) => arr
    _ => return
  }
  for block in content {
    match block {
      Object(b) =>
        match b.get("type") {
          Some(String(block_type)) =>
            if block_type == "tool_use" {
              let tool_name = match b.get("name") {
                Some(String(n)) => n
                _ => "unknown"
              }
              let tool_input = match b.get("input") {
                Some(input) => input
                _ => Json::null()
              }
              let input_str = tool_input.stringify()
              on_output(
                @types.AgentEvent::ToolCall(
                  name=tool_name,
                  input=input_str,
                ),
              )
              // Detect subagent launches (Task tool)
              if tool_name == "Task" {
                let agent_type = match tool_input {
                  Object(m) =>
                    match m.get("subagent_type") {
                      Some(String(t)) => t
                      _ => "unknown"
                    }
                  _ => "unknown"
                }
                let task_desc = match tool_input {
                  Object(m) =>
                    match m.get("description") {
                      Some(String(d)) => d
                      _ => ""
                    }
                  _ => ""
                }
                on_output(
                  @types.AgentEvent::SubAgentStart(
                    agent_type=agent_type,
                    task=task_desc,
                  ),
                )
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
}

///| Parse tool_result events
fn SubprocessBackend::parse_tool_result(
  _self : SubprocessBackend,
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let tool_name = match map.get("tool_name") {
    Some(String(n)) => n
    _ => match map.get("name") {
      Some(String(n)) => n
      _ => "unknown"
    }
  }
  let output = match map.get("content") {
    Some(String(s)) => s
    Some(other) => other.stringify()
    _ => ""
  }
  on_output(
    @types.AgentEvent::ToolResult(name=tool_name, output=output),
  )
  // Detect subagent completion
  if tool_name == "Task" {
    on_output(@types.AgentEvent::SubAgentEnd(agent_type="Task"))
  }
}

///| Parse system init event (model, tools, session)
fn SubprocessBackend::parse_system_event(
  _self : SubprocessBackend,
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let subtype = match map.get("subtype") {
    Some(String(s)) => s
    _ => ""
  }
  if subtype == "init" {
    let model = match map.get("model") {
      Some(String(m)) => m
      _ => "unknown"
    }
    let tools_count = match map.get("tools") {
      Some(Array(arr)) => arr.length()
      _ => 0
    }
    on_output(
      @types.AgentEvent::Info(
        "Session initialized: model=\{model}, tools=\{tools_count}",
      ),
    )
  }
}

///| Parse content_block_start (tool_use start, text start, thinking)
fn SubprocessBackend::parse_content_block_start(
  _self : SubprocessBackend,
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let block = match map.get("content_block") {
    Some(Object(b)) => b
    _ => return
  }
  match block.get("type") {
    Some(String(block_type)) =>
      match block_type {
        "tool_use" => {
          let name = match block.get("name") {
            Some(String(n)) => n
            _ => "unknown"
          }
          on_output(@types.AgentEvent::Info("Using tool: \{name}"))
        }
        "thinking" =>
          on_output(@types.AgentEvent::Info("Thinking..."))
        "text" =>
          on_output(@types.AgentEvent::Info("Generating response..."))
        _ => ()
      }
    _ => ()
  }
}

///| Parse result event (cost, duration, token usage)
fn SubprocessBackend::parse_result_event(
  _self : SubprocessBackend,
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let subtype = match map.get("subtype") {
    Some(String(s)) => s
    _ => ""
  }
  let buf = StringBuilder::new()
  buf.write_string("Result: \{subtype}")
  match map.get("cost_usd") {
    Some(Number(n, ..)) => buf.write_string(", cost=$\{n}")
    _ => ()
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
  // Token usage
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
