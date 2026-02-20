///| TUI application state
pub struct TuiState {
  sessions : Map[String, @types.Session]
  mut active_session_id : String
  mut active_tab : Int // index into agent list
  agent_logs : Map[String, Array[String]]
  phase_log : Array[String]
}

///| Create a new TuiState
pub fn TuiState::new() -> TuiState {
  { sessions: {}, active_session_id: "", active_tab: 0, agent_logs: {}, phase_log: [] }
}

///| Add a session
pub fn TuiState::add_session(
  self : TuiState,
  session : @types.Session,
) -> Unit {
  self.sessions[session.id] = session
  if self.active_session_id.is_empty() {
    self.active_session_id = session.id
  }
  // Initialize agent logs
  for agent in session.agents {
    self.agent_logs[agent.id] = []
  }
}

///| Get the active session
pub fn TuiState::active_session(self : TuiState) -> @types.Session? {
  self.sessions.get(self.active_session_id)
}

///| Append a log line for an agent
pub fn TuiState::append_log(
  self : TuiState,
  agent_id : String,
  line : String,
) -> Unit {
  match self.agent_logs.get(agent_id) {
    Some(logs) => logs.push(line)
    None => {
      let logs : Array[String] = [line]
      self.agent_logs[agent_id] = logs
    }
  }
}

///| Get logs for an agent (last N lines)
pub fn TuiState::get_logs(
  self : TuiState,
  agent_id : String,
  max_lines? : Int = 20,
) -> Array[String] {
  match self.agent_logs.get(agent_id) {
    Some(logs) => {
      let start = if logs.length() > max_lines {
        logs.length() - max_lines
      } else {
        0
      }
      let result : Array[String] = []
      for i = start; i < logs.length(); i = i + 1 {
        result.push(logs[i])
      }
      result
    }
    None => []
  }
}

///| Switch to next tab
pub fn TuiState::next_tab(self : TuiState) -> Unit {
  match self.active_session() {
    Some(session) => {
      let count = session.agents.length()
      if count > 0 {
        self.active_tab = (self.active_tab + 1) % count
      }
    }
    None => ()
  }
}

///| Switch to previous tab
pub fn TuiState::prev_tab(self : TuiState) -> Unit {
  match self.active_session() {
    Some(session) => {
      let count = session.agents.length()
      if count > 0 {
        self.active_tab = (self.active_tab + count - 1) % count
      }
    }
    None => ()
  }
}

///| Create OrchestratorCallbacks that update TuiState
pub fn TuiState::make_callbacks(
  self : TuiState,
) -> @types.OrchestratorCallbacks {
  {
    on_agent_output: fn(agent_id, line) { self.append_log(agent_id, line) },
    on_agent_complete: fn(agent_id, _result) {
      self.append_log(agent_id, "[completed]")
    },
    on_task_start: fn(_task_id, _desc, _agent_id) {  },
    on_task_complete: fn(_task_id, _status) {  },
    on_task_assign: fn(_task_id, _agent_id) {  },
    on_review_start: fn(_task_id, _reviewer_id) {  },
    on_review_complete: fn(task_id, verdict) {
      self.phase_log.push("Review \{task_id}: \{verdict}")
    },
    on_phase_change: fn(_session_id, phase) {
      self.phase_log.push("Phase: \{phase}")
    },
    on_session_complete: fn(_session_id) {
      self.phase_log.push("[session complete]")
    },
    on_info: fn(_msg) {  },
  }
}
