///| AgentBackend trait for executing tasks
pub(open) trait AgentBackend {
  run(
    Self,
    task : String,
    system_prompt : String,
    on_output : (@types.AgentEvent) -> Unit,
  ) -> @types.AgentResult
  name(Self) -> String
  set_session_id(Self, String) -> Unit
  get_session_id(Self) -> String
}

///| BoxedBackend for dynamic dispatch
pub struct BoxedBackend {
  inner : &AgentBackend
}

///| Create a new BoxedBackend
pub fn BoxedBackend::new(backend : &AgentBackend) -> BoxedBackend {
  { inner: backend }
}

///| Run the backend
pub fn BoxedBackend::run(
  self : BoxedBackend,
  task : String,
  system_prompt : String,
  on_output : (@types.AgentEvent) -> Unit,
) -> @types.AgentResult {
  self.inner.run(task, system_prompt, on_output)
}

///| Get the backend name
pub fn BoxedBackend::name(self : BoxedBackend) -> String {
  self.inner.name()
}

///| Set session id for resume
pub fn BoxedBackend::set_session_id(
  self : BoxedBackend,
  session_id : String,
) -> Unit {
  self.inner.set_session_id(session_id)
}

///| Get session id
pub fn BoxedBackend::get_session_id(self : BoxedBackend) -> String {
  self.inner.get_session_id()
}
