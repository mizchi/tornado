///|
/// Agent kind - which provider/tool to use
pub(all) enum AgentKind {
  ClaudeCode
  Codex
  Mock
} derive(Eq, Show)

///|
/// Agent role in the orchestration
pub(all) enum AgentRole {
  Dev
  Review
  Planner
  Verifier
} derive(Eq, Show)

///|
/// Runtime status of an agent
pub(all) enum AgentStatus {
  Idle
  Running
  Completed
  Failed(String)
} derive(Eq, Show)

///|
/// Configuration for a single agent
pub(all) struct AgentConfig {
  id : String
  kind : AgentKind
  role : AgentRole
  model : String?
  system_prompt : String?
  working_dir : String
  max_iterations : Int
}

///|
/// Status of a task in the pipeline
pub(all) enum TaskStatus {
  Pending
  InProgress(String) // agent_id
  Done
  Failed(String)
} derive(Eq, Show)

///|
/// A unit of work assigned to an agent
pub(all) struct Task {
  id : String
  description : String
  parent_id : String?
  mut status : TaskStatus
  mut result : String?
  mut review : ReviewResult?
}

///|
/// Review verdict from the review agent
pub(all) enum ReviewVerdict {
  Approved
  NeedsChanges(Array[String])
  Rejected(String)
} derive(Eq, Show)

///|
/// Result of a code review
pub(all) struct ReviewResult {
  reviewer_id : String
  verdict : ReviewVerdict
  summary : String
  file_path : String
} derive(Show)

///|
/// Status of the overall session
pub(all) enum SessionStatus {
  Active
  Completed
  Failed(String)
} derive(Eq, Show)

///|
/// Phase of the orchestrator
pub(all) enum OrchestratorPhase {
  Decomposing
  Assigning
  Executing
  Reviewing
  Iterating
  Finalizing
} derive(Eq, Show)

///|
/// A session represents a single orchestration run
pub(all) struct Session {
  id : String
  user_task : String
  mut status : SessionStatus
  mut current_phase : OrchestratorPhase
  agents : Array[AgentConfig]
  tasks : Array[Task]
}

///|
/// Callbacks for the orchestrator to notify the UI
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
  on_save : () -> Unit // persist milestones state
}

///|
/// Create noop callbacks for testing
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
    on_save: fn() {  },
  }
}

///|
/// Events emitted by an agent during execution
pub(all) enum AgentEvent {
  OutputLine(String)
  Info(String)
  ToolCall(name~ : String, input~ : String)
  ToolResult(name~ : String, output~ : String)
  SubAgentStart(agent_type~ : String, task~ : String)
  SubAgentEnd(agent_type~ : String)
  StatusChange(AgentStatus)
  SessionId(String)
  Usage(
    input_tokens~ : Int,
    output_tokens~ : Int,
    cache_read~ : Int,
    cache_write~ : Int,
    cost_usd~ : Double
  )
}

///|
/// Result of an agent's execution
pub(all) struct AgentResult {
  content : String
  status : AgentStatus
  error : String?
  session_id : String
}

///|
/// Create a new session
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

///|
/// Create a new task
pub fn Task::new(
  id : String,
  description : String,
  parent_id? : String? = None,
) -> Task {
  { id, description, parent_id, status: Pending, result: None, review: None }
}

///|
/// Mark task as in-progress with assigned agent
pub fn Task::assign(self : Task, agent_id : String) -> Unit {
  self.status = InProgress(agent_id)
}

///|
/// Mark task as done with result
pub fn Task::complete(self : Task, result : String) -> Unit {
  self.status = Done
  self.result = Some(result)
}

///|
/// Mark task as failed
pub fn Task::fail(self : Task, error : String) -> Unit {
  self.status = Failed(error)
}

///|
/// Check if task is pending
pub fn Task::is_pending(self : Task) -> Bool {
  self.status == Pending
}

///|
/// Check if task is done
pub fn Task::is_done(self : Task) -> Bool {
  self.status == Done
}

// --- Ralph Loop types ---

///|
/// Status of a milestone in the ralph loop
pub(all) enum MilestoneStatus {
  Pending
  InProgress
  Done
  Failed(String)
} derive(Eq, Show)

///|
/// A milestone containing grouped tasks
pub(all) struct Milestone {
  id : String
  goal : String
  mut status : MilestoneStatus
  mut tasks : Array[RalphTask]
  mut current_wave : Int
  mut summary : String
}

///|
/// A task within the ralph loop
pub(all) struct RalphTask {
  id : String
  description : String
  wave : Int
  mut status : TaskStatus
  mut result : String?
  mut plan_doc : String?
}

///|
/// Get all tasks in a specific wave
pub fn Milestone::get_wave_tasks(
  self : Milestone,
  wave : Int,
) -> Array[RalphTask] {
  let result : Array[RalphTask] = []
  for t in self.tasks {
    if t.wave == wave {
      result.push(t)
    }
  }
  result
}

///|
/// Check if milestone has undone tasks
pub fn Milestone::has_undone_tasks(self : Milestone) -> Bool {
  self.tasks
  .iter()
  .any(fn(t) {
    match t.status {
      Pending | InProgress(_) => true
      _ => false
    }
  })
}

///|
/// Get the next wave number that has pending tasks
pub fn Milestone::next_wave_number(self : Milestone) -> Int? {
  let mut min_wave : Int? = None
  for t in self.tasks {
    match t.status {
      Pending | InProgress(_) =>
        match min_wave {
          None => min_wave = Some(t.wave)
          Some(w) => if t.wave < w { min_wave = Some(t.wave) }
        }
      _ => ()
    }
  }
  min_wave
}

///|
/// Phase of the ralph loop state machine
pub(all) enum RalphPhase {
  LoadingMilestones
  Planning(String)
  ExecutingWave(String, Int)
  Verifying(String, Int)
  Reworking(String, Int)
  MilestoneComplete(String)
  AllComplete
} derive(Eq, Show)

///|
/// Verdict from the verifier agent
pub(all) enum VerifierVerdict {
  Approved
  NeedsRework(Array[String])
  MilestoneFailed(String)
} derive(Eq, Show)
