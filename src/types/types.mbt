///| Agent kind - which provider/tool to use
pub(all) enum AgentKind {
  ClaudeCode
  Codex
  Api
  Mock
} derive(Eq, Show)

///| Agent role in the orchestration
pub(all) enum AgentRole {
  Dev
  Review
  Orchestrator
} derive(Eq, Show)

///| Runtime status of an agent
pub(all) enum AgentStatus {
  Idle
  Running
  Completed
  Failed(String)
  Aborted
} derive(Eq, Show)

///| Configuration for a single agent
pub(all) struct AgentConfig {
  id : String
  kind : AgentKind
  role : AgentRole
  model : String?
  system_prompt : String?
  working_dir : String
  max_iterations : Int
}

///| Status of a task in the pipeline
pub(all) enum TaskStatus {
  Pending
  InProgress(String) // agent_id
  Done
  Failed(String)
} derive(Eq, Show)

///| A unit of work assigned to an agent
pub(all) struct Task {
  id : String
  description : String
  parent_id : String?
  mut status : TaskStatus
  mut result : String?
  mut review : ReviewResult?
}

///| Review verdict from the review agent
pub(all) enum ReviewVerdict {
  Approved
  NeedsChanges(Array[String])
  Rejected(String)
} derive(Eq, Show)

///| Result of a code review
pub(all) struct ReviewResult {
  reviewer_id : String
  verdict : ReviewVerdict
  summary : String
  file_path : String
} derive(Show)

///| Status of the overall session
pub(all) enum SessionStatus {
  Active
  Completed
  Failed(String)
} derive(Eq, Show)

///| Phase of the orchestrator
pub(all) enum OrchestratorPhase {
  Decomposing
  Assigning
  Executing
  Reviewing
  Iterating
  Finalizing
} derive(Eq, Show)

///| A session represents a single orchestration run
pub(all) struct Session {
  id : String
  user_task : String
  mut status : SessionStatus
  mut current_phase : OrchestratorPhase
  agents : Array[AgentConfig]
  tasks : Array[Task]
}

///| Callbacks for the orchestrator to notify the UI
pub(all) struct OrchestratorCallbacks {
  on_agent_output : (String, String) -> Unit // (agent_id, line)
  on_agent_complete : (String, String) -> Unit // (agent_id, result)
  on_task_start : (String, String, String) -> Unit // (task_id, description, agent_id)
  on_task_complete : (String, String) -> Unit // (task_id, status)
  on_task_assign : (String, String) -> Unit // (task_id, agent_id)
  on_review_start : (String, String) -> Unit // (task_id, reviewer_id)
  on_review_complete : (String, ReviewVerdict) -> Unit // (task_id, verdict)
  on_phase_change : (String, OrchestratorPhase) -> Unit // (session_id, phase)
  on_session_complete : (String) -> Unit // (session_id)
  on_info : (String) -> Unit // generic info message
}

///| Create noop callbacks for testing
pub fn OrchestratorCallbacks::noop() -> OrchestratorCallbacks {
  {
    on_agent_output: fn(_agent_id, _line) {  },
    on_agent_complete: fn(_agent_id, _result) {  },
    on_task_start: fn(_task_id, _desc, _agent_id) {  },
    on_task_complete: fn(_task_id, _status) {  },
    on_task_assign: fn(_task_id, _agent_id) {  },
    on_review_start: fn(_task_id, _reviewer_id) {  },
    on_review_complete: fn(_task_id, _verdict) {  },
    on_phase_change: fn(_session_id, _phase) {  },
    on_session_complete: fn(_session_id) {  },
    on_info: fn(_msg) {  },
  }
}

///| Events emitted by an agent during execution
pub(all) enum AgentEvent {
  OutputLine(String)
  ToolCall(name~ : String, input~ : String)
  StatusChange(AgentStatus)
  SessionId(String)
}

///| Result of an agent's execution
pub(all) struct AgentResult {
  content : String
  status : AgentStatus
  error : String?
}

///| Create a new session
pub fn Session::new(
  id : String,
  user_task : String,
  agents : Array[AgentConfig],
) -> Session {
  {
    id,
    user_task,
    status: Active,
    current_phase: Decomposing,
    agents,
    tasks: [],
  }
}

///| Create a new task
pub fn Task::new(
  id : String,
  description : String,
  parent_id? : String? = None,
) -> Task {
  { id, description, parent_id, status: Pending, result: None, review: None }
}

///| Mark task as in-progress with assigned agent
pub fn Task::assign(self : Task, agent_id : String) -> Unit {
  self.status = InProgress(agent_id)
}

///| Mark task as done with result
pub fn Task::complete(self : Task, result : String) -> Unit {
  self.status = Done
  self.result = Some(result)
}

///| Mark task as failed
pub fn Task::fail(self : Task, error : String) -> Unit {
  self.status = Failed(error)
}

///| Check if task is pending
pub fn Task::is_pending(self : Task) -> Bool {
  self.status == Pending
}

///| Check if task is done
pub fn Task::is_done(self : Task) -> Bool {
  self.status == Done
}
