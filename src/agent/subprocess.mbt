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
  let buf = StringBuilder::new()
  let mut has_error = false
  let error_buf = StringBuilder::new()
  @ffi.exec_stream(
    "claude",
    args_json.stringify(),
    fn(line) {
      // Parse session_id from init or result events
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
      // Extract session_id from raw JSONL (init or result events)
      self.try_extract_session_id(line, on_output)
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

///| Extract session_id from a JSONL line and emit event
fn SubprocessBackend::try_extract_session_id(
  self : SubprocessBackend,
  line : String,
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let json = @json.parse(line) catch { _ => return }
  match json {
    Object(map) =>
      match map.get("session_id") {
        Some(String(sid)) =>
          if not(sid.is_empty()) && self.session_id != sid {
            self.session_id = sid
            on_output(@types.AgentEvent::SessionId(sid))
          }
        _ => ()
      }
    _ => ()
  }
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
