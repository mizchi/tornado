///|
/// Main ralph loop state machine
pub struct RalphLoop {
  config : @config.ProjectConfig
  milestone_manager : MilestoneManager
  planner : PlannerAgent?
  verifier : VerifierAgent?
  backends : Map[String, @agent.BoxedBackend]
  callbacks : @types.OrchestratorCallbacks
  mut current_phase : @types.RalphPhase
  max_rework_attempts : Int
}

///|
/// Create a new ralph loop
pub fn RalphLoop::new(
  config : @config.ProjectConfig,
  milestone_manager : MilestoneManager,
  backends : Map[String, @agent.BoxedBackend],
  callbacks : @types.OrchestratorCallbacks,
  lang? : String = "en",
) -> RalphLoop {
  let planner_id = find_agent_id(config, @types.AgentRole::Planner)
  let verifier_id = find_agent_id(config, @types.AgentRole::Verifier)
  let planner : PlannerAgent? = match planner_id {
    Some(id) => Some(PlannerAgent::new(agent_id=id, lang~))
    None => None
  }
  let verifier : VerifierAgent? = match verifier_id {
    Some(id) => Some(VerifierAgent::new(agent_id=id, lang~))
    None => None
  }
  {
    config,
    milestone_manager,
    planner,
    verifier,
    backends,
    callbacks,
    current_phase: @types.RalphPhase::LoadingMilestones,
    max_rework_attempts: config.max_rework_attempts,
  }
}

///|
/// Run the ralph loop to completion
pub fn RalphLoop::run(self : RalphLoop) -> Unit {
  self.current_phase = LoadingMilestones
  emit_info(self, "Ralph loop started")
  while true {
    // Get next pending milestone
    let milestone = self.milestone_manager.next_pending_milestone()
    match milestone {
      None => {
        self.current_phase = AllComplete
        emit_info(self, "All milestones complete")
        return
      }
      Some(m) => {
        let success = self.run_milestone(m)
        if !(success) {
          emit_info(self, "Milestone \{m.id} failed")
        }
      }
    }
  }
}

///|
/// Run a single milestone through planning, execution, and verification
fn RalphLoop::run_milestone(
  self : RalphLoop,
  milestone : @types.Milestone,
) -> Bool {
  // Plan if no tasks
  if milestone.tasks.is_empty() {
    match self.planner {
      Some(planner) => {
        self.current_phase = Planning(milestone.id)
        emit_info(self, "Planning milestone: \{milestone.id}")
        let planner_backend = find_backend(self.backends, planner.agent_id)
        match planner_backend {
          Some(backend) => {
            let tasks = planner.plan(
              milestone,
              backend,
              "",
              self.milestone_manager,
              on_event=fn(e) { handle_event(self, planner.agent_id, e) },
            )
            if tasks.is_empty() {
              emit_info(self, "Planner produced no tasks for \{milestone.id}")
              milestone.status = Failed("No tasks planned")
              return false
            }
            milestone.tasks = tasks
          }
          None => {
            emit_info(self, "No backend found for planner")
            milestone.status = Failed("No planner backend")
            return false
          }
        }
      }
      None => emit_info(self, "No planner configured, skipping planning")
    }
  }
  // Execute waves
  milestone.status = @types.MilestoneStatus::InProgress
  while self.milestone_manager.has_undone_tasks(milestone) {
    let wave = self.milestone_manager.next_wave_number(milestone)
    match wave {
      None => break
      Some(wave_num) => {
        let success = self.run_wave(milestone, wave_num)
        if !(success) {
          milestone.status = Failed("Wave \{wave_num} failed")
          return false
        }
      }
    }
  }
  milestone.status = Done
  self.current_phase = MilestoneComplete(milestone.id)
  emit_info(self, "Milestone \{milestone.id} complete")
  true
}

///|
/// Run a single wave: execute tasks, then verify
fn RalphLoop::run_wave(
  self : RalphLoop,
  milestone : @types.Milestone,
  wave : Int,
) -> Bool {
  self.current_phase = ExecutingWave(milestone.id, wave)
  emit_info(self, "Executing wave \{wave} of \{milestone.id}")
  let tasks = self.milestone_manager.get_wave_tasks(milestone, wave)
  // Find builder backend (first Dev agent)
  let builder_id = find_agent_id(self.config, @types.AgentRole::Dev)
  let builder_backend = match builder_id {
    Some(id) => find_backend(self.backends, id)
    None => None
  }
  match builder_backend {
    None => {
      emit_info(self, "No builder backend found")
      return false
    }
    Some(backend) => {
      let bid = builder_id.unwrap()
      // Execute each pending/failed task sequentially
      for task in tasks {
        match task.status {
          Done => continue // Skip already-completed tasks
          _ => ()
        }
        task.status = InProgress(bid)
        emit_info(self, "Running task \{task.id}: \{task.description}")
        let result = backend.run(task.description, "", fn(e) {
          handle_event(self, bid, e)
        })
        match result.status {
          Completed => {
            task.status = Done
            task.result = Some(result.content)
            emit_info(self, "Task \{task.id} completed")
          }
          _ => {
            let err = result.error.unwrap_or("unknown error")
            task.status = Failed(err)
            task.result = Some(result.content)
            emit_info(self, "Task \{task.id} failed: \{err}")
          }
        }
      }
    }
  }
  // Verify wave
  let wave_results = collect_wave_results(tasks)
  let accepted = self.verify_wave(milestone, wave, wave_results, 0)
  if accepted {
    // Mark all wave tasks as Done so has_undone_tasks won't re-trigger
    for task in tasks {
      match task.status {
        Done => ()
        _ => {
          emit_info(self, "Task \{task.id} accepted despite status")
          task.status = Done
        }
      }
    }
  }
  accepted
}

///|
/// Verify a wave with rework loop
fn RalphLoop::verify_wave(
  self : RalphLoop,
  milestone : @types.Milestone,
  wave : Int,
  wave_results : Array[(String, String)],
  attempt : Int,
) -> Bool {
  match self.verifier {
    None =>
      // No verifier configured, auto-approve
      true
    Some(verifier) => {
      self.current_phase = Verifying(milestone.id, wave)
      emit_info(
        self,
        "Verifying wave \{wave} of \{milestone.id} (attempt \{attempt + 1})",
      )
      let verifier_backend = find_backend(self.backends, verifier.agent_id)
      match verifier_backend {
        None => {
          emit_info(self, "No verifier backend found, auto-approving")
          true
        }
        Some(backend) => {
          let verdict = verifier.verify(
            milestone,
            wave,
            wave_results,
            backend,
            "",
            on_event=fn(e) { handle_event(self, verifier.agent_id, e) },
          )
          match verdict {
            Approved => {
              emit_info(self, "Wave \{wave} approved")
              true
            }
            NeedsRework(items) => {
              if attempt >= self.max_rework_attempts {
                emit_info(
                  self,
                  "Max rework attempts reached for wave \{wave}, accepting as-is",
                )
                return true
              }
              self.current_phase = Reworking(milestone.id, wave)
              emit_info(
                self,
                "Rework needed for wave \{wave}: \{items.length()} issues",
              )
              // Re-execute failed tasks
              let reworked = self.rework_tasks(milestone, wave, items)
              self.verify_wave(milestone, wave, reworked, attempt + 1)
            }
            MilestoneFailed(reason) => {
              emit_info(self, "Milestone failed: \{reason}")
              milestone.status = Failed(reason)
              false
            }
          }
        }
      }
    }
  }
}

///|
/// Re-execute tasks that need rework
fn RalphLoop::rework_tasks(
  self : RalphLoop,
  milestone : @types.Milestone,
  wave : Int,
  feedback : Array[String],
) -> Array[(String, String)] {
  let tasks = self.milestone_manager.get_wave_tasks(milestone, wave)
  let builder_id = find_agent_id(self.config, @types.AgentRole::Dev)
  let builder_backend = match builder_id {
    Some(id) => find_backend(self.backends, id)
    None => None
  }
  // Build feedback text from verifier issues
  let feedback_text = feedback.iter().fold(
    init="",
    fn(acc, item) { acc + "- " + item + "\n" },
  )
  match builder_backend {
    None => collect_wave_results(tasks)
    Some(backend) => {
      let bid = builder_id.unwrap()
      for task in tasks {
        // Re-execute all tasks in the wave (verifier flagged the wave for rework)
        match task.status {
          Failed(_) | Pending | Done => {
            task.status = InProgress(bid)
            let rework_prompt = task.description +
              "\n\nFeedback from verification:\n" +
              feedback_text
            let result = backend.run(rework_prompt, "", fn(e) {
              handle_event(self, bid, e)
            })
            match result.status {
              Completed => {
                task.status = Done
                task.result = Some(result.content)
              }
              _ => {
                let err = result.error.unwrap_or("rework failed")
                task.status = Failed(err)
                task.result = Some(result.content)
              }
            }
          }
          _ => () // InProgress, skip
        }
      }
      collect_wave_results(tasks)
    }
  }
}

// --- Internal helpers ---

///|
fn find_agent_id(
  config : @config.ProjectConfig,
  role : @types.AgentRole,
) -> String? {
  for agent in config.agents {
    if agent.role == role {
      return Some(agent.id)
    }
  }
  None
}

///|
fn find_backend(
  backends : Map[String, @agent.BoxedBackend],
  id : String,
) -> @agent.BoxedBackend? {
  backends.get(id)
}

///|
fn collect_wave_results(
  tasks : Array[@types.RalphTask],
) -> Array[(String, String)] {
  let results : Array[(String, String)] = []
  for task in tasks {
    let content = match task.result {
      Some(r) => r
      None => "(no output)"
    }
    results.push((task.id, content))
  }
  results
}

///|
fn handle_event(
  rl : RalphLoop,
  agent_id : String,
  event : @types.AgentEvent,
) -> Unit {
  match event {
    OutputLine(line) => (rl.callbacks.on_agent_output)(agent_id, line)
    Info(msg) => (rl.callbacks.on_info)(msg)
    _ => ()
  }
}

///|
fn emit_info(rl : RalphLoop, msg : String) -> Unit {
  (rl.callbacks.on_info)(msg)
}
