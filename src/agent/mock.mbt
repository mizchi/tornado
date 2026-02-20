///| MockBackend for testing with deterministic responses
pub struct MockBackend {
  responses : Map[String, String] // task pattern -> response
  default_response : String
  call_history : Array[(String, String)] // (task, system_prompt)
}

///| Create a new MockBackend with default response
pub fn MockBackend::new(
  default_response? : String = "mock response",
) -> MockBackend {
  { responses: {}, default_response, call_history: [] }
}

///| Add a response for a specific task pattern
pub fn MockBackend::add_response(
  self : MockBackend,
  task_pattern : String,
  response : String,
) -> Unit {
  self.responses[task_pattern] = response
}

///| Get the call history
pub fn MockBackend::get_history(
  self : MockBackend,
) -> Array[(String, String)] {
  self.call_history
}

///| Find matching response for the task
fn MockBackend::find_response(self : MockBackend, task : String) -> String {
  // Simple prefix matching
  for entry in self.responses {
    let (pattern, response) = entry
    if task.contains(pattern) {
      return response
    }
  }
  self.default_response
}

///| AgentBackend implementation for MockBackend
impl AgentBackend for MockBackend with run(self, task, system_prompt, on_output) {
  self.call_history.push((task, system_prompt))
  on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Running))
  let response = self.find_response(task)
  on_output(@types.AgentEvent::OutputLine(response))
  on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Completed))
  { content: response, status: Completed, error: None }
}

///| AgentBackend implementation for MockBackend
impl AgentBackend for MockBackend with name(_self) {
  "mock"
}

///|
impl AgentBackend for MockBackend with set_session_id(_self, _sid) {  }

///|
impl AgentBackend for MockBackend with get_session_id(_self) {
  ""
}

///| Wrap in BoxedBackend for dynamic dispatch
pub fn MockBackend::boxed(self : MockBackend) -> BoxedBackend {
  BoxedBackend::new(self)
}

///| Create a MockBackend that always fails
pub fn MockBackend::failing(error_msg : String) -> MockBackend {
  {
    responses: { "": error_msg },
    default_response: error_msg,
    call_history: [],
  }
}

///| FailingMockBackend always returns a failure
pub struct FailingMockBackend {
  error_msg : String
  mut call_count : Int
}

///| Create a new FailingMockBackend
pub fn FailingMockBackend::new(
  error_msg? : String = "mock error",
) -> FailingMockBackend {
  { error_msg, call_count: 0 }
}

///| AgentBackend implementation for FailingMockBackend
impl AgentBackend for FailingMockBackend with run(
  self,
  _task,
  _system_prompt,
  on_output,
) {
  self.call_count += 1
  on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Running))
  on_output(
    @types.AgentEvent::StatusChange(@types.AgentStatus::Failed(self.error_msg)),
  )
  {
    content: "",
    status: @types.AgentStatus::Failed(self.error_msg),
    error: Some(self.error_msg),
  }
}

///| AgentBackend implementation for FailingMockBackend
impl AgentBackend for FailingMockBackend with name(_self) {
  "failing-mock"
}

///|
impl AgentBackend for FailingMockBackend with set_session_id(_self, _sid) {  }

///|
impl AgentBackend for FailingMockBackend with get_session_id(_self) {
  ""
}

///| Wrap in BoxedBackend for dynamic dispatch
pub fn FailingMockBackend::boxed(
  self : FailingMockBackend,
) -> BoxedBackend {
  BoxedBackend::new(self)
}
